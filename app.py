"""Candlepoint menu bar companion for macOS."""

from __future__ import annotations

import atexit
import os
import threading
import time
import webbrowser
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import URLError

import rumps
from PyObjCTools import AppHelper

from scanner import (MAX_SAFE_UNIVERSE, SERVER, ScannerService, get_state,
                     request_scan, should_request_scan)
from signals import GROUPS, SYMBOL, Signal, SignalMonitor


APP: "CandlepointMenu | None" = None


@rumps.notifications
def open_notification(info: dict) -> None:
    symbol = info.get("symbol")
    if APP is not None and isinstance(symbol, str) and SYMBOL.fullmatch(symbol):
        APP.open_symbol(symbol)


class CandlepointMenu(rumps.App):
    def __init__(self) -> None:
        super().__init__("Candlepoint Menu", title="C", quit_button=None)
        trading_dir = Path(os.environ.get("CANDLEPOINT_TRADING_DIR",
                                          Path(__file__).resolve().parent.parent / "trading"))
        self.service = ScannerService(trading_dir)
        self.monitor = SignalMonitor(Path.home() / "Library/Application Support/Candlepoint Menu/state.json")
        self.unread: set[str] = set()
        self.current_status = "Starting…"
        self.current_scan = None
        self._poll_lock = threading.Lock()
        self._last_requested_scan = None
        self._last_request_time = 0.0
        atexit.register(self.service.stop)
        self._render()
        rumps.Timer(self._begin_poll, 15).start()
        self._begin_poll(None)

    def _begin_poll(self, _sender) -> None:
        if self._poll_lock.acquire(blocking=False):
            threading.Thread(target=self._poll, daemon=True).start()

    def _poll(self) -> None:
        try:
            self.service.ensure_running()
            payload = get_state()
            fresh = self.monitor.update(payload)
            if should_request_scan(payload, datetime.now(timezone.utc)):
                scan = payload["updated_at"]
                if (scan != self._last_requested_scan or
                        time.monotonic() - self._last_request_time >= 600):
                    request_scan()
                    self._last_requested_scan = scan
                    self._last_request_time = time.monotonic()
            AppHelper.callAfter(self._show_state, payload, fresh)
        except (OSError, URLError, ValueError) as exc:
            message = "Starting scanner…" if self.service.owns_scanner else f"Scanner unavailable: {exc}"
            AppHelper.callAfter(self._show_error, message)
        finally:
            self._poll_lock.release()

    def _show_state(self, payload: dict, fresh: list[Signal]) -> None:
        previous_status = self.current_status
        notification_error = False
        for signal in fresh:
            self.unread.add(signal.key)
            try:
                rumps.notification("New Candlepoint signal", signal.symbol,
                                   signal.label, data={"symbol": signal.symbol})
            except RuntimeError:
                notification_error = True
        status = payload.get("status", "Unknown")
        scanned = payload.get("scanned", 0)
        universe = payload.get("universe", 0)
        if status == "Scanning":
            self.current_status = f"Scanning {scanned}/{universe} markets…"
        elif status == "Ready":
            stamp = payload.get("updated_at", "")
            self.current_status = f"Updated {stamp[:16].replace('T', ' ')} UTC"
            if universe > MAX_SAFE_UNIVERSE:
                self.current_status += " · Auto scan paused: too many markets"
            elif payload.get("errors"):
                self.current_status += f" · Auto scan paused: {payload['errors']} market errors"
        else:
            self.current_status = status
        if notification_error:
            self.current_status += " · macOS notifications unavailable"
        scan = payload.get("updated_at")
        if scan != self.current_scan or self.current_status != previous_status or fresh:
            self.current_scan = scan
            self._render()

    def _show_error(self, message: str) -> None:
        if self.current_status != message:
            self.current_status = message
            self._render()

    def _render(self) -> None:
        self.title = f"C • {len(self.unread)}" if self.unread else "C"
        self.menu.clear()
        self.menu.add(rumps.MenuItem(self.current_status))
        self.menu.add(rumps.separator)
        if self.monitor.signals:
            for group, title in GROUPS.items():
                signals = [signal for signal in self.monitor.signals if signal.group == group]
                if not signals:
                    continue
                parent = rumps.MenuItem(f"{title} ({len(signals)})")
                for signal in signals:
                    label = f"● {signal.label}" if signal.key in self.unread else signal.label
                    parent.add(rumps.MenuItem(label, callback=lambda _, s=signal: self.open_signal(s)))
                self.menu.add(parent)
        else:
            self.menu.add(rumps.MenuItem("No signals in the latest scan"))
        self.menu.add(rumps.separator)
        self.menu.add(rumps.MenuItem("Open Candlepoint", callback=lambda _: webbrowser.open(SERVER)))
        self.menu.add(rumps.MenuItem("Refresh menu", callback=self._begin_poll))
        self.menu.add(rumps.MenuItem("Quit", callback=self._quit))

    def open_signal(self, signal: Signal) -> None:
        self.unread.discard(signal.key)
        self._render()
        webbrowser.open(signal.url(SERVER))

    def open_symbol(self, symbol: str) -> None:
        self.unread = {key for key in self.unread
                       if not any(signal.key == key and signal.symbol == symbol
                                  for signal in self.monitor.signals)}
        self._render()
        webbrowser.open(f"{SERVER}/coin/{symbol}")

    def _quit(self, _sender) -> None:
        self.service.stop()
        rumps.quit_application()


if __name__ == "__main__":
    APP = CandlepointMenu()
    APP.run()
