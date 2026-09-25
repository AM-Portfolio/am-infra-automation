#!/usr/bin/env python3
"""Replace inline Kind-fleet hostAliases with shared values-overlay valueFile."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(r"F:\am-repos\am-repos\am-gitops\prod")
OVERLAY = "          - $imageValues/prod/values-overlays/hostaliases-kind-fleet-vps.yaml"

HA_RE = re.compile(
    r"(?ms)^[ \t]*# Kind-fleet VPS: pin stores to exposer IPv4[^\r\n]*\r?\n"
    r"[ \t]*hostAliases:\r?\n"
    r"(?:[ \t]+-[^\r\n]*\r?\n|[ \t]+ip:[^\r\n]*\r?\n|[ \t]+hostnames:\r?\n|[ \t]+-[ \t]+\"[^\"]+\"\r?\n)+"
)


def read(p: Path) -> str:
    return p.read_bytes().decode("latin-1")


def patch(path: Path) -> str:
    text = read(path)
    orig = text
    text, n = HA_RE.subn("", text)
    if not n:
        return f"skip {path.relative_to(ROOT)} (no ha block)"

    if "hostaliases-kind-fleet-vps.yaml" not in text:
        for sep in ("\r\n", "\n"):
            needle = f"        valueFiles:{sep}"
            if needle in text:
                text = text.replace(needle, needle + OVERLAY + sep, 1)
                break

    text = text.replace("\r\n", "\n").replace("\r", "\n")
    path.write_text(text, encoding="utf-8", newline="\n")
    return f"patched {path.relative_to(ROOT)} n={n} overlay={'hostaliases-kind-fleet-vps' in text}"


def main() -> None:
    for sub in ("apps", "agents"):
        for p in sorted((ROOT / sub).glob("*.yaml")):
            if "172.18.0.6" in read(p):
                print(patch(p))


if __name__ == "__main__":
    main()
