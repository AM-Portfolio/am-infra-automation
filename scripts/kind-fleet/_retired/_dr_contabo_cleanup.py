#!/usr/bin/env python3
"""Line-based DR Contabo cleanup + hostAliases overlay (no catastrophic regex)."""
from __future__ import annotations

from pathlib import Path

DR = Path(r"F:\am-repos\am-repos\am-gitops\dr")
OVERLAY = "          - $imageValues/dr/values-overlays/hostaliases-kind-fleet-vps.yaml"
JAVA = '            JAVA_TOOL_OPTIONS: "-Djava.net.preferIPv4Stack=true"'


def strip_hostaliases_block(lines: list[str]) -> list[str]:
    """Remove top-level helm values hostAliases: ... blocks (incl. Contabo / empty)."""
    out: list[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.lstrip(" ")
        # Match "          hostAliases:" or "          hostAliases: []"
        if stripped.startswith("hostAliases:") and line.startswith("          "):
            # skip this line and following list items / nested under it
            i += 1
            while i < len(lines):
                nxt = lines[i]
                if not nxt.strip():
                    i += 1
                    continue
                # still indented deeper than hostAliases key (more than 10 spaces typically)
                if nxt.startswith("            ") or nxt.startswith("\t"):
                    i += 1
                    continue
                # same-level or less → done
                break
            continue
        out.append(line)
        i += 1
    return out


def ensure_overlay(lines: list[str]) -> list[str]:
    text = "\n".join(lines)
    if "hostaliases-kind-fleet-vps.yaml" in text:
        return lines
    out: list[str] = []
    for i, line in enumerate(lines):
        out.append(line)
        if line.strip() == "valueFiles:":
            out.append(OVERLAY)
    return out


def ensure_java(lines: list[str]) -> list[str]:
    text = "\n".join(lines)
    if "preferIPv4Stack" in text:
        return lines
    out: list[str] = []
    for line in lines:
        out.append(line)
        if line.strip() == "env:":
            out.append(JAVA)
    return out


def process(path: Path) -> None:
    raw = path.read_bytes().decode("latin-1")
    lines = raw.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    # keep trailing structure
    had_trailing = lines and lines[-1] == ""
    lines = strip_hostaliases_block(lines)
    text = "\n".join(lines)
    text = text.replace("corp-dev.asrax.in", "corp-dr.asrax.in")
    text = text.replace("growthbook-dev.asrax.in", "growthbook-dr.asrax.in")
    lines = text.split("\n")
    lines = ensure_overlay(lines)
    lines = ensure_java(lines)
    body = "\n".join(lines)
    if had_trailing and not body.endswith("\n"):
        body += "\n"
    path.write_text(body, encoding="utf-8", newline="\n")
    print("ok", path.relative_to(DR))


def main() -> None:
    for sub in ("apps", "agents"):
        for p in sorted((DR / sub).glob("*.yaml")):
            if p.name in ("am-asrax-ui.yaml", "am-ai-gateway.yaml", "am-mkt-portal-ui.yaml", "n8n.yaml"):
                # still fix corp/overlay if needed for UI that talks stores — skip n8n/UI
                if p.name == "n8n.yaml":
                    continue
            process(p)


if __name__ == "__main__":
    main()
