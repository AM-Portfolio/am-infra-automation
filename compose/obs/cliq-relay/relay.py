#!/usr/bin/env python3
"""Minimal Grafana → Zoho Cliq webhook relay for the VPS2 obs hub.

No DB / Temporal. Formats a compact Cliq card from Grafana unified-alerting
webhooks and POSTs to ZOHO_CLIQ_WEBHOOK_URL. Full Alert Ops UI stays in
am-obs-platform alerting-runtime when Kind/Vault is available.
"""
from __future__ import annotations

import json
import os
import re
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

CLIQ_URL = os.environ.get("ZOHO_CLIQ_WEBHOOK_URL", "").strip()
GRAFANA_URL = os.environ.get(
    "GRAFANA_EXTERNAL_URL",
    os.environ.get("ALERT_OPS_UI_BASE", "https://grafana.asrax.in"),
).rstrip("/")
ONCALL = os.environ.get("ALERT_ONCALL_MENTION", "").strip()
LISTEN = os.environ.get("CLIQ_RELAY_LISTEN", "0.0.0.0:8080")

SEVERITY = {
    "critical": ("CRITICAL", "🔴"),
    "error": ("ERROR", "🔴"),
    "high": ("HIGH", "🟠"),
    "warning": ("WARNING", "🟡"),
    "info": ("INFO", "🔵"),
}


def _clean(raw: str, labels: dict[str, Any]) -> str:
    text = re.sub(r"\s+", " ", (raw or "").replace("[no value]", "")).strip()
    if text:
        return text
    name = str(labels.get("alertname") or labels.get("alert_id") or "Alert")
    where = str(labels.get("env") or labels.get("namespace") or "").strip()
    return f"{name} in {where}" if where else name


def _parse_ts(raw: Any) -> datetime | None:
    text = str(raw or "").strip()
    if not text or text.startswith("0001-01-01"):
        return None
    try:
        # Grafana uses RFC3339; tolerate trailing Z and fractional seconds.
        return datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None


def _format_duration(seconds: float) -> str:
    total = max(0, int(round(seconds)))
    days, rem = divmod(total, 86400)
    hours, rem = divmod(rem, 3600)
    minutes, secs = divmod(rem, 60)
    parts: list[str] = []
    if days:
        parts.append(f"{days}d")
    if hours or days:
        parts.append(f"{hours}h")
    if minutes or hours or days:
        parts.append(f"{minutes}m")
    parts.append(f"{secs}s")
    return " ".join(parts)


def _resolved_duration(alert: dict[str, Any]) -> tuple[str | None, str | None, str | None]:
    """Return (started, ended, duration) display strings for a resolved alert."""
    started = _parse_ts(alert.get("startsAt"))
    ended = _parse_ts(alert.get("endsAt")) or datetime.now(timezone.utc)
    if started is None:
        return None, None, None
    if ended.tzinfo is None:
        ended = ended.replace(tzinfo=timezone.utc)
    if started.tzinfo is None:
        started = started.replace(tzinfo=timezone.utc)
    duration = _format_duration((ended - started).total_seconds())
    return (
        started.astimezone(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC"),
        ended.astimezone(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC"),
        duration,
    )


def _to_cliq(payload: dict[str, Any]) -> dict[str, Any]:
    status = str(payload.get("status") or "firing").lower()
    alerts = payload.get("alerts") or [{}]
    primary = alerts[0] if isinstance(alerts[0], dict) else {}
    # Prefer an alert that matches the webhook status (resolved batch may mix).
    for item in alerts:
        if isinstance(item, dict) and str(item.get("status") or "").lower() == status:
            primary = item
            break
    labels = primary.get("labels") or {}
    annotations = primary.get("annotations") or {}

    alert_name = str(labels.get("alertname") or "Alert")
    sev_key = str(labels.get("severity") or "unknown").lower()
    sev_label, sev_emoji = SEVERITY.get(sev_key, ("UNKNOWN", "⚪"))
    env = str(labels.get("env") or labels.get("environment") or "unknown")
    app = str(
        labels.get("application")
        or labels.get("service")
        or labels.get("deployment")
        or labels.get("alert_id")
        or ""
    )
    service = str(
        labels.get("service")
        or labels.get("deployment")
        or labels.get("application")
        or labels.get("pod")
        or ""
    )
    namespace = str(labels.get("namespace") or "")
    probe_set = str(labels.get("probe_set") or "")
    summary = _clean(
        str(annotations.get("summary") or annotations.get("description") or ""),
        labels,
    )
    runbook = str(annotations.get("runbook") or annotations.get("runbook_url") or "")
    open_url = str(
        primary.get("generatorURL")
        or payload.get("externalURL")
        or f"{GRAFANA_URL}/alerting/list"
    )
    resolved = status == "resolved" or str(primary.get("status") or "").lower() == "resolved"
    started_s, ended_s, duration_s = (
        _resolved_duration(primary) if resolved else (None, None, None)
    )

    who = service or app or alert_name
    if resolved:
        title = f"✅ RESOLVED · {sev_label} · {who}"
        headline = (
            f"Alert resolved: {who}"
            + (f" (total downtime {duration_s})" if duration_s else "")
        )
    else:
        title = f"{sev_emoji} FIRING · {sev_label} · {who}"
        headline = f"Alert firing: {who}"

    where = " · ".join(
        p
        for p in (
            f"env={env}" if env != "unknown" else "",
            f"service={service}" if service else "",
            f"ns={namespace}" if namespace else "",
            f"app={app}" if app and app != service else "",
            f"team={labels.get('team')}" if labels.get("team") else "",
        )
        if p
    )
    rows = [{"Field": "Status", "Value": "RESOLVED" if resolved else "FIRING"}]
    rows.append({"Field": "Summary", "Value": summary})
    if resolved and duration_s:
        rows.append({"Field": "Total resolved time", "Value": duration_s})
    if resolved and started_s:
        rows.append({"Field": "Started", "Value": started_s})
    if resolved and ended_s:
        rows.append({"Field": "Resolved at", "Value": ended_s})
    if where:
        rows.append({"Field": "Where", "Value": where})
    if service:
        rows.append({"Field": "Service", "Value": service})
    if namespace:
        rows.append({"Field": "Namespace", "Value": namespace})
    if probe_set:
        rows.append({"Field": "Probe set", "Value": probe_set})
    # Restart count / HTTP status often arrives as the evaluated $value in summary;
    # also surface common label keys when present.
    for key, label in (
        ("restarts", "Restarts"),
        ("restart_count", "Restarts"),
        ("value", "Value"),
        ("pod", "Pod"),
        ("deployment", "Deployment"),
    ):
        if labels.get(key):
            rows.append({"Field": label, "Value": str(labels[key])})
    # Prefer annotation value when Grafana puts the numeric series value there.
    if annotations.get("value"):
        rows.append({"Field": "Metric value", "Value": str(annotations["value"])})
    if labels.get("alert_id"):
        rows.append({"Field": "Alert id", "Value": str(labels["alert_id"])})

    buttons = [
        {
            "label": "Open alert",
            "type": "+",
            "action": {"type": "open.url", "data": {"web": open_url}},
        }
    ]
    if runbook.startswith("http") and "wiki.asrax.in" not in runbook and "example.com" not in runbook:
        buttons.append(
            {
                "label": "Runbook",
                "type": "+",
                "action": {"type": "open.url", "data": {"web": runbook}},
            }
        )

    mention = ""
    if ONCALL and not resolved:
        mention = ONCALL if ONCALL.startswith("@") else f"@{ONCALL}"
    text_bits = [p for p in (mention, headline) if p]
    text = "\n".join(text_bits) if text_bits else "\u200b"

    return {
        "text": text[:1500],
        "card": {"theme": "modern-inline", "title": title[:200]},
        "slides": [
            {"type": "table", "data": {"headers": ["Field", "Value"], "rows": rows}}
        ],
        "buttons": buttons[:4],
    }


def _post_cliq(payload: dict[str, Any]) -> tuple[int, dict[str, Any]]:
    if not CLIQ_URL or CLIQ_URL.startswith("http://127.0.0.1"):
        return 503, {"ok": False, "reason": "ZOHO_CLIQ_WEBHOOK_URL not configured"}
    body = json.dumps(_to_cliq(payload)).encode("utf-8")
    req = urllib.request.Request(
        CLIQ_URL,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            resp.read()
            return 200, {"ok": True, "cliq_status": resp.status}
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")[:300]
        print(f"cliq HTTP {exc.code}: {detail}", file=sys.stderr)
        return 502, {"ok": False, "error": f"cliq_http_{exc.code}", "detail": detail}
    except Exception as exc:  # noqa: BLE001
        print(f"cliq post failed: {exc}", file=sys.stderr)
        return 502, {"ok": False, "error": str(exc)[:300]}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args: Any) -> None:
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def _send(self, code: int, obj: dict[str, Any]) -> None:
        raw = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self) -> None:  # noqa: N802
        path = self.path.split("?", 1)[0]
        if path in ("/healthz", "/readyz", "/"):
            self._send(
                200,
                {
                    "ok": True,
                    "cliq_configured": bool(CLIQ_URL)
                    and not CLIQ_URL.startswith("http://127.0.0.1"),
                },
            )
            return
        self._send(404, {"ok": False, "error": "not_found"})

    def do_POST(self) -> None:  # noqa: N802
        path = self.path.split("?", 1)[0]
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        if path not in ("/alert", "/"):
            self._send(404, {"ok": False, "error": "not_found"})
            return
        try:
            payload = json.loads(raw.decode("utf-8") or "{}")
            if not isinstance(payload, dict):
                raise ValueError("payload must be object")
        except Exception as exc:  # noqa: BLE001
            self._send(400, {"ok": False, "error": f"bad_json:{exc}"})
            return
        code, result = _post_cliq(payload)
        self._send(code, result)


def main() -> int:
    host, _, port_s = LISTEN.partition(":")
    port = int(port_s or "8080")
    if not CLIQ_URL:
        print("WARN: ZOHO_CLIQ_WEBHOOK_URL empty — /alert will 503", file=sys.stderr)
    httpd = ThreadingHTTPServer((host or "0.0.0.0", port), Handler)
    print(f"cliq-relay listening on {host or '0.0.0.0'}:{port}", flush=True)
    httpd.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
