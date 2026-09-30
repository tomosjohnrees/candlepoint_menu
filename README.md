# Candlepoint Menu

A macOS menu bar companion for [Candlepoint](https://github.com/tomosjohnrees/candlepoint). It shows current signals by category, marks new ones in the menu bar, sends a macOS notification for each new signal, and opens the signal's Candlepoint coin page when you click a menu item or its notification. It runs as an accessory app, so it has no Dock icon.

## Start

Keep this repository beside the `trading` repository, or set `CANDLEPOINT_TRADING_DIR` to the directory containing Candlepoint's `app.py`. Double-click **Candlepoint Menu.app** to launch without opening Terminal or showing a Dock icon. You can also run:

```sh
./start.command
```

The first launch creates `.venv` and installs `rumps` and PyObjC. Allow notifications for Python if macOS prompts. The app uses Candlepoint at `http://127.0.0.1:8765`. If it is already running there, the menu connects to it. Otherwise the menu starts the sibling scanner itself and stops that scanner when you quit.

The menu checks the local scanner every 15 seconds. Once the last successful scan is ten minutes old, it requests another scan. It waits for the scan to finish before showing new signals. The first scan establishes a baseline, so existing signals do not flood Notification Center. A small cursor file in `~/Library/Application Support/Candlepoint Menu/` prevents repeat alerts after a restart.

## Binance request budget

The menu's local status checks use no Binance requests. A full Candlepoint scan fetches up to two kline sets per USDT market and one per BTC market. Binance currently assigns weight 2 to each kline call, 80 to each all-symbol 24-hour ticker call, and 20 to each exchange-info call. The scanner makes two of each discovery call. At the menu's **600-market maximum** for automatic scans, the worst-case base request weight is **2,600** per scan, below Binance's documented **6,000 weight per minute** limit. The menu starts its own scanner with at most 300 markets per quote asset. It pauses automatic requests when an already-running scanner reports more than 600 markets or any market errors. The scanner's built-in fallback schedule remains two hours. Other processes sharing your IP can use the same Binance allowance, so the budget is a guard, not a guarantee.

Binance documentation: [request limits](https://developers.binance.com/en/docs/products/spot/rest-api), [market endpoint weights](https://developers.binance.com/en/docs/catalog/core-trading-spot-trading/api/rest-api/market), [exchange-info weight](https://developers.binance.com/en/docs/catalog/core-trading-spot-trading/api/rest-api/general).

## Development

```sh
python3 -m unittest discover -s tests -v
```
