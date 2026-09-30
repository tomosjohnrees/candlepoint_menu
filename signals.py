"""Candlepoint signal identities and durable notification cursor."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import quote


GROUPS = {
    "matches": "Patterns",
    "watchlist": "MACD watch",
    "key_levels": "Key levels",
    "hourly_extremes": "1-hour extremes",
    "btc_weekly": "BTC weekly",
}
SYMBOL = re.compile(r"[A-Z0-9]{1,30}(?:USDT|BTC)\Z")


@dataclass(frozen=True)
class Signal:
    key: str
    group: str
    symbol: str
    label: str
    is_new: bool

    def url(self, server: str) -> str:
        return f"{server.rstrip('/')}/coin/{quote(self.symbol)}"


def signal_key(group: str, item: dict) -> str:
    """Match Candlepoint's identity rules, including level and stage transitions."""
    if group == "btc_weekly":
        parts = [group, item["symbol"], item["signals"]]
    else:
        parts = [group, item["symbol"], item.get("stage", item.get("level_signal")),
                 item.get("level_price") if group == "key_levels" else None]
    return json.dumps(parts, separators=(",", ":"), ensure_ascii=True)


def read_signals(payload: dict) -> list[Signal]:
    result = []
    for group in GROUPS:
        for item in payload.get(group, []):
            if not isinstance(item, dict):
                continue
            symbol = item.get("symbol")
            if not isinstance(symbol, str) or not SYMBOL.fullmatch(symbol):
                continue
            detail = (" · ".join(item.get("signals", [])) if group == "btc_weekly"
                      else item.get("level_signal") or item.get("stage") or
                      ("MACD improving" if group == "watchlist" else "MACD / RSI extreme"))
            result.append(Signal(signal_key(group, item), group, symbol,
                                 f"{symbol} · {detail}", item.get("is_new") is True))
    return result


class SignalMonitor:
    def __init__(self, cursor_file: Path):
        self.cursor_file = cursor_file
        try:
            self.last_scan = json.loads(cursor_file.read_text(encoding="utf-8"))["updated_at"]
        except (FileNotFoundError, OSError, ValueError, KeyError, TypeError):
            self.last_scan = None
        self.signals: list[Signal] = []

    def update(self, payload: dict) -> list[Signal]:
        if payload.get("status") != "Ready" or not payload.get("updated_at"):
            return []
        current = read_signals(payload)
        scan = payload["updated_at"]
        if scan == self.last_scan:
            self.signals = current
            return []
        fresh = ([signal for signal in current if signal.is_new]
                 if self.last_scan and payload.get("comparison_available") else [])
        self.signals = current
        self.cursor_file.parent.mkdir(parents=True, exist_ok=True)
        temp = self.cursor_file.with_suffix(".tmp")
        temp.write_text(json.dumps({"updated_at": scan}), encoding="utf-8")
        temp.replace(self.cursor_file)
        self.last_scan = scan
        return fresh
