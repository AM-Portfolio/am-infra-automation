#!/usr/bin/env python3
"""Enable Contabo preprod CSI JWT against vault.asrax.in (via local UA proxy :8201)."""
import base64
import json
import subprocess
import urllib.request

from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

KC = r"C:\Users\user\.asrax\kubeconfig.am-vps-nonprod.yaml"
TOK = json.load(open(r"C:\Users\user\.asrax\vault-prod-infra.json", encoding="utf-8"))["root_token"]
ADDR = "http://127.0.0.1:8201"


def vault(method: str, path: str, body=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(
        ADDR + "/v1/" + path,
        data=data,
        headers={"X-Vault-Token": TOK, "Content-Type": "application/json"},
        method=method,
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        raw = r.read()
        return json.loads(raw) if raw else {}


def jwks_to_pems(jwks):
    out = []
    for jwk in jwks.get("keys", []):
        n = int.from_bytes(base64.urlsafe_b64decode(jwk["n"] + "=="), "big")
        e = int.from_bytes(base64.urlsafe_b64decode(jwk["e"] + "=="), "big")
        pub = rsa.RSAPublicNumbers(e, n).public_key(default_backend())
        out.append(
            pub.public_bytes(
                serialization.Encoding.PEM,
                serialization.PublicFormat.SubjectPublicKeyInfo,
            ).decode()
        )
    return out


def main():
    jwks = json.loads(
        subprocess.check_output(["kubectl", "--kubeconfig", KC, "get", "--raw", "/openid/v1/jwks"])
    )
    contabo_pems = jwks_to_pems(jwks)
    print("contabo_jwks", len(contabo_pems))

    cfg = vault("GET", "auth/jwt-nonprod/config")["data"]
    existing = list(cfg.get("jwt_validation_pubkeys") or [])
    merged = list(existing)
    for p in contabo_pems:
        if p not in merged:
            merged.append(p)
    print("pubkeys_before", len(existing), "after", len(merged))

    vault(
        "POST",
        "auth/jwt-nonprod/config",
        {
            "jwt_validation_pubkeys": merged,
            "bound_issuer": cfg.get("bound_issuer")
            or "https://kubernetes.default.svc.cluster.local",
            "default_role": "am-backend-role-dev",
            "jwks_url": "",
            "oidc_discovery_url": "",
        },
    )
    print("jwt_config_updated")

    policy = """path "apps/data/preprod/*" {
  capabilities = ["read"]
}
path "apps/data/preprod" {
  capabilities = ["list"]
}
path "apps/metadata/preprod/*" {
  capabilities = ["list", "read"]
}
"""
    vault("PUT", "sys/policies/acl/am-backend-policy-preprod", {"policy": policy})
    print("policy_ok")

    vault(
        "POST",
        "auth/jwt-nonprod/role/am-backend-role-preprod",
        {
            "role_type": "jwt",
            "user_claim": "sub",
            "bound_audiences": ["vault"],
            "bound_claims_type": "glob",
            "bound_claims": {"sub": "system:serviceaccount:am-*-preprod:am-backend-sa"},
            "token_policies": ["am-backend-policy-preprod"],
            "token_ttl": "1h",
            "token_max_ttl": "4h",
        },
    )
    role = vault("GET", "auth/jwt-nonprod/role/am-backend-role-preprod")["data"]
    print("role_ok", role.get("bound_claims"), role.get("token_policies"))


if __name__ == "__main__":
    main()
