"""Local Candlepoint service lifecycle and conservative scan scheduling."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import Request, urlopen


SERVER = "http://127.0.0.1:8765"
SCAN_INTERVAL_SECONDS = 600
MAX_SAFE_UNIVERSE = 1000


def get_state(server: str = SERVER) -> dict:
    with urlopen(f"{server}/api/state", timeout=5) as response:
        payload = json.load(response)
    if not isinstance(payload, dict):
        raise ValueError("Invalid scanner response")
    return payload


def request_scan(server: str = SERVER) -> None:
    with urlopen(Request(f"{server}/api/scan", data=b"", method="POST"), timeout=5):
        pass


def should_request_scan(payload: dict, now: datetime) -> bool:
    if payload.get("status") != "Ready":
        return False
    universe = payload.get("universe")
    if not isinstance(universe, int) or isinstance(universe, bool) or not 0 < universe <= MAX_SAFE_UNIVERSE:
        return False
    if "429" in str(payload.get("last_error", "")) or "418" in str(payload.get("last_error", "")):
        return False
    try:
        updated = datetime.fromisoformat(payload["updated_at"].replace("Z", "+00:00"))
        if updated.tzinfo is None:
            return False
    except (KeyError, TypeError, ValueError):
        return False
    return (now - updated).total_seconds() >= SCAN_INTERVAL_SECONDS


class ScannerService:
    def __init__(self, trading_dir: Path, server: str = SERVER):
        self.trading_dir = trading_dir
        self.server = server
        self.process: subprocess.Popen | None = None

    def ensure_running(self) -> None:
        if self.process is not None and self.process.poll() is None:
            return
        try:
            get_state(self.server)
            return
        except (OSError, ValueError):
            pass
        script = self.trading_dir / "app.py"
        if not script.is_file():
            raise FileNotFoundError(f"Candlepoint scanner not found at {script}")
        environment = os.environ.copy()
        environment.update(PORT="8765", SCAN_INTERVAL_SECONDS="600", MAX_SYMBOLS="400")
        self.process = subprocess.Popen(
            [sys.executable, str(script)], cwd=self.trading_dir, env=environment,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )

    @property
    def owns_scanner(self) -> bool:
        return self.process is not None and self.process.poll() is None

    def stop(self) -> None:
        if self.owns_scanner:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
        self.process = None
