import Foundation

public struct Signal: Equatable {
    public let key: String
    public let group: String
    public let symbol: String
    public let label: String
    public let isNew: Bool

    public var url: URL {
        URL(string: "http://127.0.0.1:8765/coin/\(symbol)")!
    }
}

public enum ScanState {
    public static let interval: TimeInterval = 600
    public static let maxSafeUniverse = 600
    public static let groups: [(key: String, title: String)] = [
        ("matches", "Patterns"),
        ("watchlist", "MACD watch"),
        ("key_levels", "Key levels"),
        ("hourly_extremes", "1-hour extremes"),
        ("btc_weekly", "BTC weekly"),
    ]

    public static func signals(in state: [String: Any]) -> [Signal] {
        var result: [Signal] = []
        for group in groups {
            for item in state[group.key] as? [[String: Any]] ?? [] {
                guard let symbol = item["symbol"] as? String, validSymbol(symbol) else { continue }
                let conditions = item["signals"] as? [String] ?? []
                let stage = item["stage"] as? String ?? item["level_signal"] as? String ?? ""
                let detail: String
                switch group.key {
                case "btc_weekly": detail = conditions.joined(separator: " · ")
                case "watchlist": detail = "MACD improving"
                case "hourly_extremes": detail = "MACD / RSI extreme"
                default: detail = stage
                }
                let level = (item["level_price"] as? NSNumber)?.stringValue ?? ""
                let key = [group.key, symbol, stage, group.key == "btc_weekly" ? conditions.joined(separator: "|") : level]
                    .joined(separator: "\u{1F}")
                result.append(Signal(key: key, group: group.key, symbol: symbol,
                                     label: "\(symbol) · \(detail)", isNew: item["is_new"] as? Bool == true))
            }
        }
        return result
    }

    public static func shouldRequestScan(_ state: [String: Any], now: Date) -> Bool {
        guard state["status"] as? String == "Ready",
              let universe = state["universe"] as? Int,
              (1...maxSafeUniverse).contains(universe),
              state["errors"] as? Int == 0,
              let timestamp = state["updated_at"] as? String,
              let updated = scanDate(timestamp) else { return false }
        let error = state["last_error"] as? String ?? ""
        guard !error.contains("429"), !error.contains("418") else { return false }
        return now.timeIntervalSince(updated) >= interval
    }

    public static func scanDate(_ timestamp: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: timestamp) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: timestamp)
    }

    private static func validSymbol(_ symbol: String) -> Bool {
        symbol.range(of: #"^[A-Z0-9]{1,30}(USDT|BTC)$"#, options: .regularExpression) != nil
    }
}

public final class SignalStore {
    private let defaults: UserDefaults
    private let cursorKey: String
    public private(set) var signals: [Signal] = []

    public init(defaults: UserDefaults = .standard, cursorKey: String = "lastCompletedScan") {
        self.defaults = defaults
        self.cursorKey = cursorKey
    }

    public func update(_ state: [String: Any]) -> [Signal] {
        guard state["status"] as? String == "Ready",
              let timestamp = state["updated_at"] as? String, !timestamp.isEmpty else { return [] }
        let current = ScanState.signals(in: state)
        let previous = defaults.string(forKey: cursorKey)
        signals = current
        guard timestamp != previous else { return [] }
        defaults.set(timestamp, forKey: cursorKey)
        guard previous != nil, state["comparison_available"] as? Bool == true else { return [] }
        return current.filter(\.isNew)
    }
}
