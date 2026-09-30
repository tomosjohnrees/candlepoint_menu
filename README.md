# Candlepoint Menu

A native Swift menu bar app for [Candlepoint](https://github.com/tomosjohnrees/candlepoint). It shows current signals by category, marks new ones in the menu bar, sends macOS notifications, and opens the signal's Candlepoint coin page when you click a menu item or notification. It has no Dock icon.

## Install and start

Requires macOS 13 or later, Xcode or Swift command line tools, and the [Candlepoint scanner](https://github.com/tomosjohnrees/candlepoint). Clone both repositories into the same parent directory and build:

```sh
git clone https://github.com/tomosjohnrees/candlepoint.git
git clone https://github.com/tomosjohnrees/candlepoint_menu.git
cd candlepoint_menu
./build_app.command
```

Then double-click **Candlepoint Menu.app**. Look for **CP** on the right side of the menu bar. `start.command` builds the app if needed and launches it. Allow notifications for Candlepoint Menu if macOS prompts. The app uses Candlepoint at `http://127.0.0.1:8765`. If it is already running there, the menu connects to it. Otherwise it starts a sibling scanner named `candlepoint` or `trading` and stops that scanner when you quit.

The menu checks the local scanner every 15 seconds. Once the last successful scan is ten minutes old, it requests another scan. It waits for the scan to finish before showing new signals. Unread signals appear at the top of the menu under **New signals**, with a direct link to each coin page. Select one to clear it, or use **Mark all as seen**. Signals that disappear from a later scan leave the unread list. The first scan establishes a baseline, so existing signals do not flood Notification Center. A saved scan cursor prevents repeat alerts after a restart.

## Binance request budget

The menu's local status checks use no Binance requests. A full Candlepoint scan fetches up to two kline sets per USDT market and one per BTC market. Binance currently assigns weight 2 to each kline call, 80 to each all-symbol 24-hour ticker call, and 20 to each exchange-info call. The scanner makes two of each discovery call. At the menu's **600-market maximum** for automatic scans, the worst-case base request weight is **2,600** per scan, below Binance's documented **6,000 weight per minute** limit. The menu starts its own scanner with at most 300 markets per quote asset. It pauses automatic requests when an already-running scanner reports more than 600 markets or any market errors. The scanner's built-in fallback schedule remains two hours. Other processes sharing your IP can use the same Binance allowance, so the budget is a guard, not a guarantee.

Binance documentation: [request limits](https://developers.binance.com/en/docs/products/spot/rest-api), [market endpoint weights](https://developers.binance.com/en/docs/catalog/core-trading-spot-trading/api/rest-api/market), [exchange-info weight](https://developers.binance.com/en/docs/catalog/core-trading-spot-trading/api/rest-api/general).

## Development

```sh
swift test
```
