#!/usr/bin/env python3
"""Daily prod user-landings digest → Zoho Cliq (09:00 Asia/Kolkata).

Landed = unique anon_id with any am-product-telemetry event on the prior
IST calendar day. New = landed anon_ids absent from the prior 7 days.
Existing = landed - new. Also reports sessions + logged-in user_ids.
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from typing import Any
from zoneinfo import ZoneInfo

LOKI_URL = os.environ.get("LOKI_URL", "http://loki:3100").rstrip("/")
CLIQ_URL = os.environ.get("ZOHO_CLIQ_WEBHOOK_URL", "").strip()
GRAFANA_URL = os.environ.get(
    "GRAFANA_EXTERNAL_URL", "https://grafana.asrax.in"
).rstrip("/")
ENV = os.environ.get("DIGEST_ENV", "prod").strip() or "prod"
TZ = ZoneInfo(os.environ.get("DIGEST_TZ", "Asia/Kolkata"))
LOOKBACK_DAYS = int(os.environ.get("DIGEST_NEW_LOOKBACK_DAYS", "7"))
DASH_URL = (
    f"{GRAFANA_URL}/d/product-am-users/product-users"
    f"?var-env={ENV}&from=now-24h&to=now"
)


def _window_for_report(now: datetime | None = None) -> tuple[datetime, datetime, datetime, str]:
    """Prior IST calendar day as [day_start, day_end) in UTC + lookback start."""
    now_ist = (now or datetime.now(timezone.utc)).astimezone(TZ)
    today_start = now_ist.replace(hour=0, minute=0, second=0, microsecond=0)
    day_end = today_start
    day_start = day_end - timedelta(days=1)
    lookback_start = day_start - timedelta(days=LOOKBACK_DAYS)
    label = day_start.strftime("%Y-%m-%d")
    return (
        day_start.astimezone(timezone.utc),
        day_end.astimezone(timezone.utc),
        lookback_start.astimezone(timezone.utc),
        label,
    )


def _query_range_metric(expr: str, start: datetime, end: datetime, step: str = "1h") -> list[dict]:
    qs = urllib.parse.urlencode(
        {
            "query": expr,
            "start": int(start.timestamp() * 1e9),
            "end": int(end.timestamp() * 1e9),
            "step": step,
        }
    )
    url = f"{LOKI_URL}/loki/api/v1/query_range?{qs}"
    req = urllib.request.Request(url, headers={"Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=180) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")[:400]
        raise RuntimeError(f"loki HTTP {exc.code}: {detail}") from exc
    if data.get("status") != "success":
        raise RuntimeError(f"loki query_range failed: {str(data)[:400]}")
    return (data.get("data") or {}).get("result") or []


def _ids_from_series(rows: list[dict], label: str) -> set[str]:
    out: set[str] = set()
    for row in rows:
        metric = row.get("metric") or {}
        val = str(metric.get(label) or "").strip()
        if val:
            out.add(val)
    return out


def _sum_by_label(rows: list[dict], label: str) -> dict[str, float]:
    out: dict[str, float] = {}
    for row in rows:
        metric = row.get("metric") or {}
        key = str(metric.get(label) or "unknown")
        total = 0.0
        for _, v in row.get("values") or []:
            try:
                total += float(v)
            except (TypeError, ValueError):
                pass
        out[key] = out.get(key, 0.0) + total
    return out


def collect() -> dict[str, Any]:
    day_start, day_end, lookback_start, label = _window_for_report()

    landed_expr = (
        f'sum by (anon_id) (count_over_time('
        f'{{job="am-product-telemetry", env="{ENV}"}} '
        f'| json | anon_id != "" [1h]))'
    )
    sessions_expr = (
        f'sum by (session_id) (count_over_time('
        f'{{job="am-product-telemetry", env="{ENV}", event="session_start"}} '
        f'| json | session_id != "" [1h]))'
    )
    users_expr = (
        f'sum by (user_id) (count_over_time('
        f'{{job="am-product-telemetry", env="{ENV}"}} '
        f'| json | user_id != "" [1h]))'
    )
    platform_expr = (
        f'sum by (platform) (count_over_time('
        f'{{job="am-product-telemetry", env="{ENV}"}} [1h]))'
    )

    landed = _ids_from_series(
        _query_range_metric(landed_expr, day_start, day_end), "anon_id"
    )
    prior = _ids_from_series(
        _query_range_metric(landed_expr, lookback_start, day_start, step="6h"),
        "anon_id",
    )
    new_ids = landed - prior
    existing = landed & prior
    sessions = _ids_from_series(
        _query_range_metric(sessions_expr, day_start, day_end), "session_id"
    )
    logged_in = _ids_from_series(
        _query_range_metric(users_expr, day_start, day_end), "user_id"
    )
    platforms = _sum_by_label(
        _query_range_metric(platform_expr, day_start, day_end), "platform"
    )

    return {
        "day": label,
        "env": ENV,
        "landed": len(landed),
        "new": len(new_ids),
        "existing": len(existing),
        "sessions": len(sessions),
        "logged_in": len(logged_in),
        "platforms": platforms,
        "lookback_days": LOOKBACK_DAYS,
        "day_start": day_start.isoformat(),
        "day_end": day_end.isoformat(),
    }


def _to_cliq(stats: dict[str, Any]) -> dict[str, Any]:
    plat = stats.get("platforms") or {}
    plat_line = " · ".join(
        f"{k}={int(v)}" for k, v in sorted(plat.items(), key=lambda x: -x[1]) if k
    )
    rows = [
        {"Field": "Date (IST)", "Value": str(stats["day"])},
        {"Field": "Env", "Value": str(stats["env"])},
        {"Field": "Landed devices", "Value": str(stats["landed"])},
        {
            "Field": "New",
            "Value": f'{stats["new"]} (not seen prior {stats["lookback_days"]}d)',
        },
        {"Field": "Existing", "Value": str(stats["existing"])},
        {"Field": "Sessions", "Value": str(stats["sessions"])},
        {"Field": "Logged-in users", "Value": str(stats["logged_in"])},
    ]
    if plat_line:
        rows.append({"Field": "Events by platform", "Value": plat_line})
    return {
        "text": "\u200b",
        "card": {
            "theme": "modern-inline",
            "title": f"Daily user landings · {stats['env']} · {stats['day']}"[:200],
        },
        "slides": [
            {"type": "table", "data": {"headers": ["Field", "Value"], "rows": rows}}
        ],
        "buttons": [
            {
                "label": "Product / Users",
                "type": "+",
                "action": {"type": "open.url", "data": {"web": DASH_URL}},
            }
        ],
    }


def post_cliq(stats: dict[str, Any]) -> None:
    if not CLIQ_URL or CLIQ_URL.startswith("http://127.0.0.1"):
        raise SystemExit("ZOHO_CLIQ_WEBHOOK_URL not configured")
    body = json.dumps(_to_cliq(stats)).encode("utf-8")
    req = urllib.request.Request(
        CLIQ_URL,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=20) as resp:
        resp.read()
        print(
            f"cliq ok status={resp.status} day={stats['day']} landed={stats['landed']}",
            flush=True,
        )


def main() -> int:
    dry = "--dry-run" in sys.argv
    print(f"digest env={ENV} loki={LOKI_URL} dry_run={dry}", flush=True)
    stats = collect()
    print(json.dumps(stats, indent=2, default=str), flush=True)
    if dry:
        return 0
    post_cliq(stats)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # noqa: BLE001
        print(f"digest failed: {exc}", file=sys.stderr)
        raise
