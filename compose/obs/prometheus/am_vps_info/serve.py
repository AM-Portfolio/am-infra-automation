#!/usr/bin/env python3
"""Serve static OpenMetrics/Prometheus text with the correct Content-Type."""
from __future__ import annotations

from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

BODY = (Path(__file__).resolve().parent / "metrics").read_bytes()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:  # noqa: N802
        if self.path not in ("/metrics", "/"):
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
        self.send_header("Content-Length", str(len(BODY)))
        self.end_headers()
        self.wfile.write(BODY)

    def log_message(self, fmt: str, *args) -> None:  # noqa: A003
        return


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", 9100), Handler).serve_forever()
