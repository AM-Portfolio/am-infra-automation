#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path

PULL = """\
            image:
              imagePullSecrets:
                - name: ghcr-creds
                - name: github-registry-secret
"""

NAMES = [
    "am-oms.yaml",
    "am-parser.yaml",
    "am-logging.yaml",
    "am-email-extractor.yaml",
    "am-cloudinary-manager.yaml",
    "am-notification.yaml",
    "am-subscription.yaml",
    "am-api-gateway.yaml",
]


def main() -> None:
    apps = Path(r"F:\am-repos\am-repos\am-gitops\prod\apps")
    for name in NAMES:
        path = apps / name
        text = path.read_text(encoding="utf-8")
        if "imagePullSecrets:" in text:
            print(f"skip {name}")
            continue
        # Insert imagePullSecrets after global.vault csi enabled, before next sibling under global or vault:
        pat = re.compile(
            r"(?m)^(          global:\n"
            r"            vault:\n"
            r"(?:              .*\n)+?"
            r"                enabled: true\n)"
        )
        m = pat.search(text)
        if not m:
            print(f"FAIL structure {name}")
            continue
        text = text[: m.end()] + PULL + text[m.end() :]
        path.write_text(text, encoding="utf-8", newline="\n")
        print(f"patched {name}")


if __name__ == "__main__":
    main()
