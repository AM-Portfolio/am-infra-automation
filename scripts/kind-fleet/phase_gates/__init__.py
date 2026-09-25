"""Kind-fleet phase gates (4a–4f). Replace ad-hoc tmp-p4*.sh probes.

Usage (on VPS or laptop with kube/vault access):

  python -m phase_gates --env prod --wave 4f
  python -m phase_gates --env prod --wave all

Env files (prod VPS defaults):
  /data/am-state/vault-prod-infra.json
  /data/am-state/credentials/prod-keycloak-admin.env
  /data/am-state/kubeconfig.am-prod-apps.yaml
  /data/am-state/kubeconfig.am-prod-infra.yaml
  /data/am-state/kubeconfig.am-prod-platform.yaml
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import ssl
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Callable

UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
)


class GateError(Exception):
    pass


def _env_defaults(env: str) -> dict[str, str]:
    if env == "prod":
        return {
            "domain": "asrax.in",
            "am_host": "https://am.asrax.in",
            "auth_host": "https://auth.asrax.in",
            "vault_addr": "https://vault.asrax.in",
            "vault_keys": "/data/am-state/vault-prod-infra.json",
            "kc_env": "/data/am-state/credentials/prod-keycloak-admin.env",
            "kube_apps": "/data/am-state/kubeconfig.am-prod-apps.yaml",
            "kube_infra": "/data/am-state/kubeconfig.am-prod-infra.yaml",
            "kube_platform": "/data/am-state/kubeconfig.am-prod-platform.yaml",
            "realm": "am-realm",
        }
    if env == "dev":
        home = Path.home()
        return {
            "domain": "asrax.in",
            "am_host": "https://am-dev.asrax.in",
            "auth_host": "https://auth-dev.asrax.in",
            "vault_addr": "https://vault-dev.asrax.in",
            "vault_keys": str(home / ".asrax" / "vault-dev-infra.json"),
            "kc_env": str(home / ".asrax" / "credentials.d" / "keycloak-kind-fleet-dev.env"),
            "kube_apps": str(home / ".asrax" / "kubeconfig.am-dev-apps.yaml"),
            "kube_infra": str(home / ".asrax" / "kubeconfig.am-dev-infra.yaml"),
            "kube_platform": str(home / ".asrax" / "kubeconfig.am-dev-platform.yaml"),
            "realm": "am-realm",
        }
    raise GateError(f"unsupported env={env}")


def _parse_env_file(path: str) -> dict[str, str]:
    out: dict[str, str] = {}
    p = Path(path)
    if not p.is_file():
        return out
    for line in p.read_text(encoding="utf-8-sig").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        out[k.strip()] = v.strip().strip("\"'")
    return out


def _vault_root_token(cfg: dict[str, str]) -> str:
    data = json.loads(Path(cfg["vault_keys"]).read_text(encoding="utf-8-sig"))
    tok = data.get("root_token") or data.get("token") or ""
    if not tok:
        raise GateError(f"no root_token in {cfg['vault_keys']}")
    return tok


def _http_json(
    method: str,
    url: str,
    *,
    headers: dict[str, str] | None = None,
    data: bytes | None = None,
    timeout: int = 30,
) -> tuple[int, Any]:
    ctx = ssl._create_unverified_context()
    h = {"User-Agent": UA}
    if headers:
        h.update(headers)
    req = urllib.request.Request(url, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(req, context=ctx, timeout=timeout) as resp:
            raw = resp.read()
            code = resp.status
            if not raw:
                return code, None
            try:
                return code, json.loads(raw.decode())
            except json.JSONDecodeError:
                return code, raw.decode(errors="replace")
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            body = json.loads(raw.decode())
        except Exception:
            body = raw.decode(errors="replace")
        return e.code, body


def _kubectl(kubeconfig: str, *args: str) -> str:
    cmd = ["kubectl", "--kubeconfig", kubeconfig, *args]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    if r.returncode != 0:
        raise GateError(f"kubectl failed: {' '.join(cmd)}\n{r.stderr.strip()}")
    return r.stdout.strip()


def gate_4a_vault_csi(cfg: dict[str, str]) -> None:
    """Vault apps mount readable; CSI role path contract."""
    tok = _vault_root_token(cfg)
    env = cfg.get("_env", "prod")
    path = f"apps/data/{env}/infra/postgres"
    code, body = _http_json(
        "GET",
        f"{cfg['vault_addr']}/v1/{path}",
        headers={"X-Vault-Token": tok},
    )
    if code != 200:
        raise GateError(f"4a vault read {path} → {code} {body}")
    keys = sorted((body.get("data") or {}).get("data", {}).keys())
    if "POSTGRES_HOST" not in keys and "host" not in keys:
        raise GateError(f"4a postgres secret missing host keys: {keys}")
    print(f"PASS 4a_vault_csi read {path} keys={len(keys)}")


def gate_4b_argo(cfg: dict[str, str]) -> None:
    """Apps cluster registered; prod roots present (best-effort via kubectl on platform)."""
    kube = cfg["kube_platform"]
    if not Path(kube).is_file():
        print(f"SKIP 4b_argo missing kubeconfig {kube}")
        return
    out = _kubectl(kube, "get", "appprojects", "-n", "argocd", "-o", "name")
    if "am-prod" not in out and "am-dev" not in out:
        # project name varies; just ensure argocd ns answers
        _kubectl(kube, "get", "ns", "argocd")
    apps = _kubectl(kube, "get", "applications", "-n", "argocd", "-o", "name")
    if "prod-apps-root" not in apps and "dev-apps-root" not in apps and "apps-root" not in apps:
        print(f"WARN 4b_argo no *apps-root in: {apps[:200]}")
    print("PASS 4b_argo argocd reachable")


def gate_4c_edge(cfg: dict[str, str]) -> None:
    code, body = _http_json("GET", f"{cfg['am_host']}/")
    if code != 200:
        raise GateError(f"4c UI {cfg['am_host']}/ → {code}")
    code2, body2 = _http_json("GET", f"{cfg['am_host']}/gateway")
    if code2 not in (401, 403):
        # some gateways return 401 JSON; 200 without auth is wrong
        if code2 == 200:
            raise GateError("4c /gateway returned 200 without token (expected 401)")
        raise GateError(f"4c /gateway → {code2} {str(body2)[:120]}")
    print(f"PASS 4c_edge UI={code} gateway={code2}")


def _password_grant(cfg: dict[str, str], username: str, password: str) -> str:
    token_url = f"{cfg['auth_host']}/realms/{cfg['realm']}/protocol/openid-connect/token"
    secret = _modern_ui_client_secret(cfg)
    attempts: list[tuple[str, str | None]] = []
    if secret:
        attempts.append(("am-modern-ui", secret))
    attempts.append(("admin-cli", None))
    for client_id, client_secret in attempts:
        form: dict[str, str] = {
            "grant_type": "password",
            "client_id": client_id,
            "username": username,
            "password": password,
            "scope": "openid profile email",
        }
        if client_secret:
            form["client_secret"] = client_secret
        code, body = _http_json(
            "POST",
            token_url,
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            data=urllib.parse.urlencode(form).encode(),
        )
        if code == 200 and isinstance(body, dict) and body.get("access_token"):
            print(f"grant_ok {client_id}")
            return body["access_token"]
        print(f"grant_try {client_id} → {code}")
    raise GateError("password-grant failed for all clients")


def _modern_ui_client_secret(cfg: dict[str, str]) -> str | None:
    """Resolve am-modern-ui client secret from Vault oidc path or Keycloak admin API."""
    tok = _vault_root_token(cfg)
    env = cfg.get("_env", "prod")
    for path in (
        f"apps/data/{env}/oidc/am-modern-ui",
        f"apps/data/{env}/services/am-modern-ui",
    ):
        code, body = _http_json(
            "GET",
            f"{cfg['vault_addr']}/v1/{path}",
            headers={"X-Vault-Token": tok},
        )
        if code == 200 and isinstance(body, dict):
            data = (body.get("data") or {}).get("data") or {}
            # tolerate accidental double-nest from older writers
            if isinstance(data.get("data"), dict):
                data = data["data"]
            sec = data.get("client_secret") or data.get("AM_MODERN_UI_CLIENT_SECRET")
            if sec:
                return str(sec)
    # Keycloak admin via platform NodePort (VPS)
    kube = cfg.get("kube_platform") or ""
    if not kube or not Path(kube).is_file():
        return None
    try:
        import shutil

        if not shutil.which("docker"):
            return None
        kc_ip = subprocess.check_output(
            [
                "docker",
                "inspect",
                "-f",
                "{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}",
                f"am-{cfg.get('_env', 'prod')}-platform-control-plane",
            ],
            text=True,
        ).strip().split()[0]
        kc = f"http://{kc_ip}:30808"
        admin_pass = base64.b64decode(
            subprocess.check_output(
                [
                    "kubectl",
                    "--kubeconfig",
                    kube,
                    "-n",
                    "identity",
                    "get",
                    "secret",
                    "keycloak-admin",
                    "-o",
                    "jsonpath={.data.password}",
                ],
                text=True,
            ).strip()
        ).decode()
        code, body = _http_json(
            "POST",
            f"{kc}/realms/master/protocol/openid-connect/token",
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            data=urllib.parse.urlencode(
                {
                    "client_id": "admin-cli",
                    "username": "admin",
                    "password": admin_pass,
                    "grant_type": "password",
                }
            ).encode(),
        )
        if code != 200 or not isinstance(body, dict):
            return None
        atok = body["access_token"]
        code, clients = _http_json(
            "GET",
            f"{kc}/admin/realms/{cfg['realm']}/clients?clientId=am-modern-ui",
            headers={"Authorization": f"Bearer {atok}"},
        )
        if code != 200 or not clients:
            return None
        cid = clients[0]["id"]
        code, sec = _http_json(
            "GET",
            f"{kc}/admin/realms/{cfg['realm']}/clients/{cid}/client-secret",
            headers={"Authorization": f"Bearer {atok}"},
        )
        if code == 200 and isinstance(sec, dict):
            return sec.get("value")
    except Exception as e:
        print(f"modern_ui_secret_skip {e}")
    return None


def gate_4d_identity(cfg: dict[str, str]) -> None:
    tok = _vault_root_token(cfg)
    env = cfg.get("_env", "prod")
    # test users
    code, body = _http_json(
        "GET",
        f"{cfg['vault_addr']}/v1/apps/data/{env}/infra/keycloak-test-users",
        headers={"X-Vault-Token": tok},
    )
    if code != 200:
        raise GateError(f"4d missing keycloak-test-users → {code}")
    tu = (body.get("data") or {}).get("data", {})
    user = tu.get("AM_ADMIN_TEST_USERNAME") or tu.get("admin_username") or "am-admin-test"
    password = (
        tu.get("AM_ADMIN_TEST_PASSWORD")
        or tu.get("admin_password")
        or tu.get(user)
        or ""
    )
    if len(password) < 8:
        raise GateError("4d test user password missing/short in Vault")

    # identity admin must not be fleet placeholder
    code, body = _http_json(
        "GET",
        f"{cfg['vault_addr']}/v1/apps/data/{env}/services/am-identity",
        headers={"X-Vault-Token": tok},
    )
    if code != 200:
        raise GateError(f"4d am-identity vault → {code}")
    idata = (body.get("data") or {}).get("data", {})
    admin_pw = str(idata.get("KEYCLOAK_ADMIN_PASSWORD") or "")
    if not admin_pw or admin_pw.endswith("-fleet-keycloak-admin-password"):
        raise GateError("4d KEYCLOAK_ADMIN_PASSWORD is still a fleet placeholder")

    access = _password_grant(cfg, user, password)
    # decode iss
    payload = access.split(".")[1]
    payload += "=" * ((4 - len(payload) % 4) % 4)
    claims = json.loads(base64.urlsafe_b64decode(payload))
    iss = claims.get("iss", "")
    if ":30808" in str(iss):
        raise GateError(f"4d token iss still NodePort: {iss}")

    # Protected APIs: prefer /users/me; /admin/roles is also auth-gated and valid for hard gate.
    ok_url = None
    last = None
    for path in ("/identity/users/me", "/identity/admin/roles"):
        code, body = _http_json(
            "GET",
            f"{cfg['am_host']}{path}",
            headers={"Authorization": f"Bearer {access}"},
        )
        last = (code, path, body)
        if code == 200:
            ok_url = path
            break
    if not ok_url:
        raise GateError(f"4d protected API failed last={last}")
    print(f"PASS 4d_identity {ok_url}=200 iss={iss}")


def gate_4e_market(cfg: dict[str, str]) -> None:
    """Market quote on domain (strip-prefix /market must be configured)."""
    code, body = _http_json("GET", f"{cfg['am_host']}/market/actuator/health")
    if code != 200:
        raise GateError(f"4e /market/actuator/health → {code} {str(body)[:160]}")
    code2, body2 = _http_json(
        "GET", f"{cfg['am_host']}/market/v1/market-data/quotes?symbols=RELIANCE"
    )
    if code2 != 200:
        raise GateError(f"4e quotes → {code2} {str(body2)[:200]}")
    if isinstance(body2, dict) and not body2.get("quotes"):
        raise GateError(f"4e quotes body missing quotes key: {str(body2)[:200]}")
    print(f"PASS 4e_market health={code} quotes={code2}")


def _test_user_password(cfg: dict[str, str]) -> tuple[str, str]:
    tok = _vault_root_token(cfg)
    env = cfg.get("_env", "prod")
    code, body = _http_json(
        "GET",
        f"{cfg['vault_addr']}/v1/apps/data/{env}/infra/keycloak-test-users",
        headers={"X-Vault-Token": tok},
    )
    if code != 200:
        raise GateError(f"test users vault → {code}")
    tu = (body.get("data") or {}).get("data", {})
    user = tu.get("AM_ADMIN_TEST_USERNAME") or tu.get("admin_username") or "am-admin-test"
    password = (
        tu.get("AM_ADMIN_TEST_PASSWORD")
        or tu.get("admin_password")
        or tu.get(user)
        or ""
    )
    if len(password) < 8:
        raise GateError("test user password missing/short in Vault")
    return user, password


def gate_4f_apps(cfg: dict[str, str]) -> None:
    """Portfolio → trade → doc → news/analysis domain smoke."""
    # Public health (strip-prefix already TF-owned).
    health_paths = (
        ("portfolio", "/portfolio/actuator/health"),
        ("trade", "/trade/actuator/health"),
        ("doc", "/doc/processor/actuator/health"),
        ("news", "/news/health"),
        ("analysis", "/analysis/actuator/health"),
    )
    for name, path in health_paths:
        code, body = _http_json("GET", f"{cfg['am_host']}{path}")
        # news may expose /health or actuator
        if name == "news" and code != 200:
            code, body = _http_json("GET", f"{cfg['am_host']}/news/actuator/health")
            path = "/news/actuator/health"
        if code != 200:
            raise GateError(f"4f {name} {path} → {code} {str(body)[:160]}")
        print(f"PASS 4f_{name}_health {path}={code}")

    user, password = _test_user_password(cfg)
    access = _password_grant(cfg, user, password)
    code, body = _http_json(
        "GET",
        f"{cfg['am_host']}/portfolio/v1/portfolios",
        headers={"Authorization": f"Bearer {access}"},
    )
    if code != 200:
        raise GateError(f"4f /portfolio/v1/portfolios → {code} {str(body)[:200]}")
    print(f"PASS 4f_portfolio_list code={code}")


def gate_4g_remaining(cfg: dict[str, str]) -> None:
    """Remaining apps + agents: domain health smoke + no Vault sidecars + auth still works."""
    health_paths = (
        ("parser", "/parser/actuator/health"),
        ("notification", "/notification/actuator/health"),
        ("subscription", "/subscription/actuator/health"),
        ("logging", "/logging/actuator/health"),
        ("oms_wallets", "/v1/wallets"),  # may be 401 without token — accept 200/401
    )
    for name, path in health_paths:
        code, body = _http_json("GET", f"{cfg['am_host']}{path}")
        if name == "oms_wallets":
            if code not in (200, 401, 403):
                raise GateError(f"4g {name} {path} → {code} {str(body)[:160]}")
            print(f"PASS 4g_{name} {path}={code}")
            continue
        if code != 200:
            # fallbacks
            alts = {
                "parser": ["/market/parser/actuator/health"],
                "logging": ["/logging/health"],
            }
            ok = False
            for alt in alts.get(name, []):
                code2, body2 = _http_json("GET", f"{cfg['am_host']}{alt}")
                if code2 == 200:
                    print(f"PASS 4g_{name}_health {alt}={code2}")
                    ok = True
                    break
            if not ok:
                raise GateError(f"4g {name} {path} → {code} {str(body)[:160]}")
        else:
            print(f"PASS 4g_{name}_health {path}={code}")

    # Spot-check Ready deploys + CSI volume / no vault-agent sidecar
    kube = cfg["kube_apps"]
    for ns, label in (
        ("am-apps-prod", "app.kubernetes.io/instance=am-parser-prod"),
        ("am-agents-prod", "app.kubernetes.io/instance=am-mcp-server-prod"),
    ):
        out = _kubectl(
            kube,
            "-n",
            ns,
            "get",
            "pods",
            "-l",
            label,
            "-o",
            "json",
        )
        items = json.loads(out).get("items") or []
        if not items:
            raise GateError(f"4g no pods for {ns} {label}")
        pod = items[0]
        containers = [c["name"] for c in pod["spec"].get("containers") or []]
        if any("vault-agent" in c for c in containers):
            raise GateError(f"4g vault sidecar on {pod['metadata']['name']}: {containers}")
        vols = [v.get("name") for v in pod["spec"].get("volumes") or []]
        if not any("vault" in (v or "") for v in vols):
            raise GateError(f"4g CSI vault volume missing on {pod['metadata']['name']}: {vols}")
        print(f"PASS 4g_csi_no_sidecar {ns}/{pod['metadata']['name']}")

    # Closout: password-grant + portfolio list still green (Postman core path)
    user, password = _test_user_password(cfg)
    access = _password_grant(cfg, user, password)
    code, body = _http_json(
        "GET",
        f"{cfg['am_host']}/portfolio/v1/portfolios",
        headers={"Authorization": f"Bearer {access}"},
    )
    if code != 200:
        raise GateError(f"4g closout /portfolio/v1/portfolios → {code}")
    print(f"PASS 4g_closout_portfolio_list code={code}")


GATES: dict[str, Callable[[dict[str, str]], None]] = {
    "4a": gate_4a_vault_csi,
    "4b": gate_4b_argo,
    "4c": gate_4c_edge,
    "4d": gate_4d_identity,
    "4e": gate_4e_market,
    "4f": gate_4f_apps,
    "4g": gate_4g_remaining,
}

WAVE_ALIASES = {
    "4a": ["4a"],
    "4b": ["4a", "4b"],
    "4c": ["4a", "4b", "4c"],
    "4d": ["4a", "4b", "4c", "4d"],
    "4e": ["4a", "4b", "4c", "4d", "4e"],
    "4f": ["4a", "4b", "4c", "4d", "4e", "4f"],
    "4g": ["4a", "4b", "4c", "4d", "4e", "4f", "4g"],
    "all": ["4a", "4b", "4c", "4d", "4e", "4f", "4g"],
}


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Kind-fleet phase gates")
    p.add_argument("--env", choices=("prod", "dev"), default="prod")
    p.add_argument("--wave", default="4d", help="4a|4b|4c|4d|4e|4f|4g|all")
    args = p.parse_args(argv)
    cfg = _env_defaults(args.env)
    cfg["_env"] = args.env
    waves = WAVE_ALIASES.get(args.wave, [args.wave])
    failed = 0
    for w in waves:
        fn = GATES.get(w)
        if not fn:
            print(f"UNKNOWN wave {w}", file=sys.stderr)
            failed += 1
            continue
        try:
            fn(cfg)
        except Exception as e:
            print(f"FAIL {w}: {e}", file=sys.stderr)
            failed += 1
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
