#!/usr/bin/env python3
"""Sleep until next 09:00 Asia/Kolkata, run digest.py, repeat."""
from __future__ import annotations

import os
import subprocess
import sys
import time
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

TZ = ZoneInfo(os.environ.get("DIGEST_TZ", "Asia/Kolkata"))
HOUR = int(os.environ.get("DIGEST_HOUR", "9"))
MINUTE = int(os.environ.get("DIGEST_MINUTE", "0"))
DIGEST = os.environ.get("DIGEST_SCRIPT", "/srv/digest.py")


def seconds_until_next_run(now: datetime | None = None) -> float:
    now_ist = (now or datetime.now(TZ)).astimezone(TZ)
    target = now_ist.replace(hour=HOUR, minute=MINUTE, second=0, microsecond=0)
    if now_ist >= target:
        target = target + timedelta(days=1)
    return max(1.0, (target - now_ist).total_seconds())


def main() -> int:
    run_now = "--once" in sys.argv or os.environ.get("DIGEST_RUN_ONCE", "").lower() in {
        "1",
        "true",
        "yes",
    }
    if run_now:
        print("users-digest: running once", flush=True)
        return subprocess.call([sys.executable, DIGEST, *sys.argv[1:]])

    print(
        f"users-digest scheduler: tz={TZ.key} at {HOUR:02d}:{MINUTE:02d}",
        flush=True,
    )
    while True:
        wait = seconds_until_next_run()
        print(f"users-digest: sleeping {wait:.0f}s until next run", flush=True)
        time.sleep(wait)
        print("users-digest: firing", flush=True)
        rc = subprocess.call([sys.executable, DIGEST])
        if rc != 0:
            print(f"users-digest: digest exited {rc}", flush=True)
        # Avoid double-fire in the same minute.
        time.sleep(60)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
