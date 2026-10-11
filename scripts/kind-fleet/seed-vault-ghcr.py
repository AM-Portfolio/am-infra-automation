#!/usr/bin/env python3
"""Seed Vault apps/<env>/infra/ghcr from credentials.env (no token printed).

Requires kube context with access to Contabo infra Vault (prod-infra).

Usage:
  $env:KUBECONFIG=\"$HOME/.asrax/kubeconfig.prod\"
  kubectl config use-context prod-infra
  python scripts/kind-fleet/seed-vault-ghcr.py --env prod
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path


def load_creds() -> tuple[str, str, Path]:
    home = Path(os.environ.get("ASRAX_HOME", Path.home() / ".asrax"))
    paths = [Path(os.environ["ASRAX_CREDENTIALS"])] if os.environ.get("ASRAX_CREDENTIALS") else []
    paths += [
        home / "credentials.env",
        Path("/data/am-state/credentials/credentials.env"),
        Path(f"/data/am-state/credentials/{os.environ.get('ENV', 'prod')}/credentials.env"),
    ]
    text = ""
    used: Path | None = None
    for p in paths:
        if p.exists():
            text = p.read_text(encoding="utf-8-sig", errors="ignore")
            used = p
            break
    if not text or used is None:
        raise SystemExit("no credentials.env found")

    user_m = re.search(r"(?m)^(?:GHCR_USERNAME|GITHUB_USERNAME|GITHUB_USER)=(.+)$", text)
    tok_m = (
        re.search(r"(?m)^GHCR_TOKEN=(.+)$", text)
        or re.search(r"(?m)^GITHUB_PERSONAL_ACCESS_TOKEN=(.+)$", text)
        or re.search(r"(?m)^GITHUB_TOKEN=(.+)$", text)
        or re.search(r"(?m)^GH_TOKEN=(.+)$", text)
    )
    if not tok_m:
        raise SystemExit(f"no GHCR/GITHUB token in {used}")
    user = (user_m.group(1) if user_m else "token").strip().strip('"').strip("'")
    tok = tok_m.group(1).strip().strip('"').strip("'")
    print(f"SoT {used} user={user} token_len={len(tok)} prefix={tok[:7]}")
    return user, tok, used


def vault_root_token() -> str:
    out = subprocess.check_output(
        ["kubectl", "-n", "vault", "get", "secret", "vault-unseal-keys", "-o", "json"],
        text=True,
    )
    keys = json.loads(base64.b64decode(json.loads(out)["data"]["keys.json"]))
    root = keys.get("root_token")
    if not root:
        raise SystemExit("vault-unseal-keys missing root_token")
    return root


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--env", default=os.environ.get("ENV", "prod"))
    ap.add_argument("--mount", default="apps")
    args = ap.parse_args()

    user, tok, _ = load_creds()
    root = vault_root_token()
    path = f"{args.env}/infra/ghcr"
    payload = {"username": user, "token": tok, "password": tok}

    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as f:
        json.dump(payload, f)
        local = f.name
    remote = "/tmp/ghcr-seed.json"
    try:
        raw = Path(local).read_bytes()
        # Avoid kubectl cp (breaks on Windows paths). Stream base64 into the pod.
        b64 = base64.b64encode(raw).decode("ascii")
        put_script = (
            f"echo '{b64}' | base64 -d > {remote} && "
            f"vault kv put -mount={args.mount} {path} @{remote}; "
            f"ec=$?; rm -f {remote}; exit $ec"
        )
        r = subprocess.run(
            [
                "kubectl",
                "-n",
                "vault",
                "exec",
                "vault-0",
                "--",
                "env",
                f"VAULT_TOKEN={root}",
                "/bin/sh",
                "-c",
                put_script,
            ],
            capture_output=True,
            text=True,
        )
        if r.returncode != 0:
            err = (r.stderr or r.stdout or "").replace(tok, "***").replace(root, "***")
            print(err, file=sys.stderr)
            raise SystemExit(r.returncode)

        chk = subprocess.run(
            [
                "kubectl",
                "-n",
                "vault",
                "exec",
                "vault-0",
                "--",
                "env",
                f"VAULT_TOKEN={root}",
                "vault",
                "kv",
                "get",
                "-format=json",
                f"-mount={args.mount}",
                path,
            ],
            capture_output=True,
            text=True,
        )
        if chk.returncode != 0:
            print((chk.stderr or chk.stdout).replace(tok, "***").replace(root, "***"), file=sys.stderr)
            raise SystemExit(chk.returncode)
        data = (json.loads(chk.stdout).get("data") or {}).get("data") or {}
        print(
            f"OK vault {args.mount}/data/{path} keys={sorted(data.keys())} "
            f"username={data.get('username')} token_len={len(str(data.get('token') or ''))}"
        )
    finally:
        try:
            os.unlink(local)
        except OSError:
            pass
        subprocess.run(
            ["kubectl", "-n", "vault", "exec", "vault-0", "--", "rm", "-f", remote],
            capture_output=True,
        )


if __name__ == "__main__":
    main()
