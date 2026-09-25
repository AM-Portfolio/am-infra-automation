#!/usr/bin/env python3
"""Inject Kind-fleet exposer hostAliases + preferIPv4 into prod Application YAMLs."""
from __future__ import annotations

import re
import sys
from pathlib import Path

HA_BLOCK = """\
          # Kind-fleet VPS: pin stores to exposer IPv4 (see hostaliases-kind-fleet-vps.yaml).
          hostAliases:
            - ip: "172.18.0.6"
              hostnames:
                - "redis.asrax.in"
                - "mongodb.asrax.in"
                - "mongo.asrax.in"
                - "postgres.asrax.in"
                - "kafka.asrax.in"
                - "influxdb.asrax.in"
                - "minio.asrax.in"
"""

JAVA = '            JAVA_TOOL_OPTIONS: "-Djava.net.preferIPv4Stack=true"\n'

# Apps that talk to stores on the kind net (skip pure UIs if no store env).
TARGETS = [
    "am-parser.yaml",
    "am-oms.yaml",
    "am-user-platform.yaml",
    "am-logging.yaml",
    "am-email-extractor.yaml",
    "am-cloudinary-manager.yaml",
    "am-asrax-corp.yaml",
    "am-notification.yaml",
    "am-subscription.yaml",
    # agents with redis/mongo
    "am-mcp-server.yaml",
    "am-tool-agent.yaml",
    "am-support-agent.yaml",
    "am-fin-agent.yaml",
    "am-db-agent.yaml",
    "am-qa-agents.yaml",
    "am-mkt-agents.yaml",
]


def patch_values(text: str) -> str:
    # Replace empty hostAliases: [] with exposer block
    text = re.sub(
        r"(?m)^[ \t]*# Clear Contabo hostAliases.*\n[ \t]*hostAliases:\s*\[\]\s*\n",
        HA_BLOCK,
        text,
    )
    text = re.sub(
        r"(?m)^[ \t]*hostAliases:\s*\[\]\s*\n",
        HA_BLOCK,
        text,
    )
    if "172.18.0.6" not in text:
        # Insert HA before ignoreMissingValueFiles or valueFiles under helm values
        # Prefer after env: block — find end of `values: |` yaml blob before valueFiles
        m = re.search(
            r"(?m)^(        valueFiles:|        ignoreMissingValueFiles:)",
            text,
        )
        if not m:
            raise SystemExit("cannot find valueFiles/ignoreMissing insertion point")
        text = text[: m.start()] + HA_BLOCK + text[m.start() :]

    if "preferIPv4Stack" not in text and "JAVA_TOOL_OPTIONS" not in text:
        # Insert JAVA after last INFLUX_HOST or after env: block first redis line
        if re.search(r"(?m)^[ \t]*INFLUX_HOST:", text):
            text = re.sub(
                r"(?m)^([ \t]*INFLUX_HOST:.*\n)",
                r"\1" + JAVA,
                text,
                count=1,
            )
        elif re.search(r"(?m)^[ \t]*env:\s*$", text):
            text = re.sub(
                r"(?m)^([ \t]*env:\s*\n)",
                r"\1" + JAVA,
                text,
                count=1,
            )
    return text


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    apps = root / "apps"
    agents = root / "agents"
    for name in TARGETS:
        path = apps / name if (apps / name).is_file() else agents / name
        if not path.is_file():
            print(f"skip missing {name}")
            continue
        old = path.read_text(encoding="utf-8")
        new = patch_values(old)
        if new == old:
            print(f"unchanged {path}")
            continue
        path.write_text(new, encoding="utf-8", newline="\n")
        print(f"patched {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
