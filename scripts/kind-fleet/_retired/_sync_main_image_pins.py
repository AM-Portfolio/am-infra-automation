#!/usr/bin/env python3
"""Review follow-up: pin main/preprod images, fix OMS vault, finish hostAliases."""
from __future__ import annotations

from pathlib import Path

GITOPS = Path(r"F:\am-repos\am-repos\am-gitops")
OVERLAY = "          - $imageValues/prod/values-overlays/hostaliases-kind-fleet-vps.yaml"

# Prefer preprod freeze / known CI numerics over local-* / latest / stale
TAG_UPDATES: dict[str, dict] = {
    "am-modern-ui": {
        "tag": "36121944526",
        "digest": "sha256:b55745f792c08e6324b7209b61854114950840d0b7a3f627ef9e55593384f57a",
    },
    "am-email-extractor": {"tag": "30939244123"},
    "am-cloudinary-manager": {"tag": "31211878691"},
    "am-portfolio": {"tag": "35856161500"},
    "am-trade-management-service": {"tag": "36111377819"},
    "am-fin-agent": {"tag": "35082128612"},
    "am-market-data": {"tag": "35626677247"},
    # am-oms / am-qa-agents / am-mkt-* GHCR only has local-* tags — leave as-is.
}


def write_image_tag(path: Path, tag: str, digest: str | None = None) -> None:
    lines = [
        f"# Pinned for fleet — prefer main/preprod CI numeric tags (not local-* / latest).",
        "global:",
        "  image:",
    ]
    if digest:
        lines.append(f'    digest: "{digest}"')
    lines.extend(
        [
            f'    tag: "{tag}"',
            "    imagePullSecrets:",
            "      - name: ghcr-creds",
            "",
        ]
    )
    path.write_text("\n".join(lines), encoding="utf-8", newline="\n")


def copy_prod_to_dr_latest() -> None:
    prod = GITOPS / "prod" / "image-tags"
    dr = GITOPS / "dr" / "image-tags"
    for p in sorted(dr.glob("*.yaml")):
        text = p.read_text(encoding="utf-8")
        if 'tag: "latest"' not in text and "tag: latest" not in text:
            continue
        src = prod / p.name
        if not src.exists():
            print("skip dr latest (no prod)", p.name)
            continue
        p.write_text(src.read_text(encoding="utf-8"), encoding="utf-8", newline="\n")
        print("dr<-prod", p.name)


def ensure_prod_overlay(path: Path) -> None:
    raw = path.read_bytes().decode("latin-1").replace("\r\n", "\n")
    if "hostaliases-kind-fleet-vps.yaml" in raw:
        return
    if "valueFiles:" not in raw:
        return
    lines = raw.split("\n")
    out = []
    for line in lines:
        out.append(line)
        if line.strip() == "valueFiles:":
            out.append(OVERLAY)
    path.write_text("\n".join(out), encoding="utf-8", newline="\n")
    print("overlay", path.relative_to(GITOPS))


def fix_oms_prod() -> None:
    p = GITOPS / "prod" / "apps" / "am-oms.yaml"
    text = p.read_text(encoding="utf-8")
    old = """          vault:
            enabled: true
            address: "https://vault.asrax.in"
            authPath: auth/kubernetes-apps
            role: am-backend-role
            csi:
              enabled: true
          # vault/auth inline (overlay not on GitHub yet)
          vault:
            secretPaths:
              mongodb:
                path: "apps/data/prod/infra/mongodb"
              kafka:
                path: "apps/data/prod/infra/kafka"
              identity-oidc:
                path: "apps/data/prod/services/am-identity"
              trade-management:
                path: "apps/data/prod/services/am-trade-management"
              market-data:
                path: "apps/data/prod/services/am-market-data"
"""
    new = """          vault:
            enabled: true
            address: "https://vault.asrax.in"
            authPath: auth/kubernetes-apps
            role: am-backend-role
            csi:
              enabled: true
            secretPaths:
              mongodb:
                path: "apps/data/prod/infra/mongodb"
              kafka:
                path: "apps/data/prod/infra/kafka"
              identity-oidc:
                path: "apps/data/prod/services/am-identity"
              trade-management:
                path: "apps/data/prod/services/am-trade-management"
              market-data:
                path: "apps/data/prod/services/am-market-data"
"""
    if old not in text:
        print("oms: pattern mismatch")
        return
    p.write_text(text.replace(old, new), encoding="utf-8", newline="\n")
    print("oms vault merged")


def fix_market_data_prod() -> None:
    p = GITOPS / "prod" / "apps" / "am-market-data.yaml"
    text = p.read_bytes().decode("latin-1").replace("\r\n", "\n")
    text2 = text.replace(
        "          # No laptop LAN hostAliases on VPS; exposer/DNS resolves store hosts.\n"
        "          hostAliases: []\n",
        "",
    )
    text2 = text2.replace(
        "          - $imageValues/prod/values-overlays/hostaliases-kind-local.yaml\n",
        "          - $imageValues/prod/values-overlays/hostaliases-kind-fleet-vps.yaml\n",
    )
    # growthbook-dev → growthbook for prod public host if present
    text2 = text2.replace("growthbook-dev.asrax.in", "growthbook.asrax.in")
    if "hostaliases-kind-fleet-vps.yaml" not in text2 and "valueFiles:" in text2:
        text2 = text2.replace(
            "        valueFiles:\n",
            "        valueFiles:\n" + OVERLAY + "\n",
            1,
        )
    p.write_text(text2, encoding="utf-8", newline="\n")
    print("market-data hostAliases fleet")


def main() -> None:
    for name, meta in TAG_UPDATES.items():
        for env in ("prod", "dr"):
            path = GITOPS / env / "image-tags" / f"{name}.yaml"
            if not path.exists():
                print("missing", path)
                continue
            write_image_tag(path, meta["tag"], meta.get("digest"))
            print("pin", env, name, meta["tag"])

    # mkt: no successful CI — leave local but do not invent tags
    copy_prod_to_dr_latest()
    fix_oms_prod()
    fix_market_data_prod()

    for rel in (
        "prod/apps/am-identity.yaml",
        "prod/apps/am-gateway.yaml",
        "prod/apps/am-api-gateway.yaml",
        "prod/apps/am-asrax-proxy.yaml",
        "prod/apps/am-modern-ui.yaml",
        "prod/agents/am-ai-gateway.yaml",
        "prod/agents/am-asrax-ui.yaml",
        "prod/agents/am-mkt-portal-ui.yaml",
    ):
        ensure_prod_overlay(GITOPS / rel)


if __name__ == "__main__":
    main()
