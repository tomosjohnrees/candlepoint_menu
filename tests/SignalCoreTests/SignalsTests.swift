import XCTest
@testable import SignalCore

final class SignalsTests: XCTestCase {
    private func state(_ timestamp: String, isNew: Bool = false) -> [String: Any] {
        ["status": "Ready", "updated_at": timestamp, "comparison_available": true,
         "universe": 223, "errors": 0,
         "matches": [["symbol": "NEARUSDT", "stage": "Breaking out", "is_new": isNew]]]
    }

    func testNewSignalOnlyAfterBaselineAndOnlyOnce() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SignalStore(defaults: defaults)
        XCTAssertTrue(store.update(state("2026-09-30T12:00:00+00:00", isNew: true)).isEmpty)
        let next = state("2026-09-30T12:10:00+00:00", isNew: true)
        XCTAssertEqual(store.update(next).map(\.symbol), ["NEARUSDT"])
        XCTAssertTrue(store.update(next).isEmpty)
        XCTAssertTrue(SignalStore(defaults: defaults).update(next).isEmpty)
    }

    func testScanBudgetAndTiming() {
        let now = ScanState.scanDate("2026-09-30T12:10:00+00:00")!
        var payload = state("2026-09-30T12:00:00+00:00")
        XCTAssertTrue(ScanState.shouldRequestScan(payload, now: now))
        payload["universe"] = 601
        XCTAssertFalse(ScanState.shouldRequestScan(payload, now: now))
        payload["universe"] = 100
        payload["errors"] = 1
        XCTAssertFalse(ScanState.shouldRequestScan(payload, now: now))
        payload["errors"] = 0
        payload["updated_at"] = "2026-09-30T12:01:00+00:00"
        XCTAssertFalse(ScanState.shouldRequestScan(payload, now: now))
    }

    func testSignalIdentityAndLink() {
        let near = ScanState.signals(in: state("2026-09-30T12:00:00+00:00"))[0]
        var changed = state("2026-09-30T12:10:00+00:00")
        changed["matches"] = [["symbol": "NEARUSDT", "stage": "Near breakout"]]
        let next = ScanState.signals(in: changed)[0]
        XCTAssertNotEqual(near.key, next.key)
        XCTAssertEqual(near.url.absoluteString, "http://127.0.0.1:8765/coin/NEARUSDT")
        changed["matches"] = [["symbol": "../bad", "stage": "Near breakout"]]
        XCTAssertTrue(ScanState.signals(in: changed).isEmpty)
    }

    func testUnreadSignalsStayRecentAndDisappearWhenNoLongerCurrent() {
        let unread = UnreadSignals()
        var payload = state("2026-09-30T12:00:00+00:00")
        let first = ScanState.signals(in: payload)[0]
        payload["watchlist"] = [["symbol": "FETUSDT"]]
        let second = ScanState.signals(in: payload).last!

        unread.record([first], current: [first])
        unread.record([second, second], current: [first, second])
        XCTAssertEqual(unread.signals(from: [first, second]).map(\.key), [second.key, first.key])
        XCTAssertEqual(unread.count, 2)

        unread.markSeen(first.key)
        XCTAssertEqual(unread.signals(from: [first, second]).map(\.key), [second.key])
        unread.record([], current: [first])
        XCTAssertEqual(unread.count, 0)
    }

    func testOpeningSymbolClearsAllItsUnreadSignals() {
        let unread = UnreadSignals()
        var payload = state("2026-09-30T12:00:00+00:00")
        payload["key_levels"] = [["symbol": "NEARUSDT", "level_signal": "Crossed above"]]
        payload["watchlist"] = [["symbol": "FETUSDT"]]
        let current = ScanState.signals(in: payload)
        unread.record(current, current: current)
        unread.markSeen(symbol: "NEARUSDT", current: current)
        XCTAssertEqual(unread.signals(from: current).map(\.symbol), ["FETUSDT"])
        unread.markAllSeen()
        XCTAssertEqual(unread.count, 0)
    }
}
