import AppKit
import Foundation
import SignalCore
import UserNotifications

private let server = URL(string: "http://127.0.0.1:8765")!

@main
struct CandlepointMenuMain {
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate = MenuApp()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

private final class MenuApp: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var scanner: Process?
    private let store = SignalStore()
    private var unread = Set<String>()
    private var status = "Starting…"
    private var polling = false
    private var lastRequestedScan: String?
    private var lastRequestTime = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "CP"
        statusItem.button?.toolTip = "Candlepoint signals"
        renderMenu()

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.poll() }
        poll()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if scanner?.isRunning == true { scanner?.terminate() }
    }

    private func poll() {
        guard !polling else { return }
        polling = true
        var request = URLRequest(url: server.appendingPathComponent("api/state"))
        request.timeoutInterval = 5
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.polling = false
                guard error == nil, let data,
                      let state = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    self.ensureScannerRunning()
                    return
                }
                self.handle(state)
            }
        }.resume()
    }

    private func ensureScannerRunning() {
        if scanner?.isRunning == true {
            setStatus("Starting scanner…")
            return
        }
        let root = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        let directory = ProcessInfo.processInfo.environment["CANDLEPOINT_TRADING_DIR"]
            .map(URL.init(fileURLWithPath:)) ?? root.appendingPathComponent("trading")
        let script = directory.appendingPathComponent("app.py")
        guard FileManager.default.fileExists(atPath: script.path) else {
            setStatus("Scanner unavailable — start Candlepoint")
            return
        }
        guard let python = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            setStatus("Python 3 is needed for the scanner")
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [script.path]
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        environment.merge(["PORT": "8765", "MAX_SYMBOLS": "300", "SCAN_INTERVAL_SECONDS": "7200"])
            { _, new in new }
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            scanner = process
            setStatus("Starting scanner…")
        } catch {
            setStatus("Could not start scanner: \(error.localizedDescription)")
        }
    }

    private func handle(_ state: [String: Any]) {
        let fresh = store.update(state)
        for signal in fresh {
            unread.insert(signal.key)
            let content = UNMutableNotificationContent()
            content.title = "New Candlepoint signal"
            content.subtitle = signal.symbol
            content.body = signal.label
            content.sound = .default
            content.userInfo = ["symbol": signal.symbol]
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            )
        }

        let scanStatus = state["status"] as? String ?? "Unknown"
        let universe = state["universe"] as? Int ?? 0
        if scanStatus == "Scanning" {
            setStatus("Scanning \(state["scanned"] as? Int ?? 0)/\(universe) markets…")
        } else if scanStatus == "Ready" {
            let stamp = state["updated_at"] as? String ?? ""
            var label = "Updated \(stamp.prefix(16).replacingOccurrences(of: "T", with: " ")) UTC"
            if universe > ScanState.maxSafeUniverse {
                label += " · Auto scan paused: too many markets"
            } else if let errors = state["errors"] as? Int, errors > 0 {
                label += " · Auto scan paused: \(errors) market errors"
            }
            setStatus(label)
        } else {
            setStatus(scanStatus)
        }

        if ScanState.shouldRequestScan(state, now: Date()),
           let stamp = state["updated_at"] as? String,
           stamp != lastRequestedScan || Date().timeIntervalSince(lastRequestTime) >= 600 {
            lastRequestedScan = stamp
            lastRequestTime = Date()
            var request = URLRequest(url: server.appendingPathComponent("api/scan"))
            request.httpMethod = "POST"
            request.timeoutInterval = 5
            URLSession.shared.dataTask(with: request).resume()
        }
    }

    private func setStatus(_ value: String) {
        status = value
        renderMenu()
    }

    private func renderMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: status, action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        for group in ScanState.groups {
            let matches = store.signals.filter { $0.group == group.key }
            guard !matches.isEmpty else { continue }
            let heading = NSMenuItem(title: "\(group.title) (\(matches.count))", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for signal in matches {
                let marker = unread.contains(signal.key) ? "● " : ""
                let item = NSMenuItem(title: marker + signal.label, action: #selector(openSignal(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = ["symbol": signal.symbol, "key": signal.key]
                submenu.addItem(item)
            }
            heading.submenu = submenu
            menu.addItem(heading)
        }
        if store.signals.isEmpty {
            menu.addItem(NSMenuItem(title: "No signals in the latest scan", action: nil, keyEquivalent: ""))
        }
        menu.addItem(.separator())
        let dashboard = NSMenuItem(title: "Open Candlepoint", action: #selector(openDashboard), keyEquivalent: "")
        dashboard.target = self
        menu.addItem(dashboard)
        let refresh = NSMenuItem(title: "Refresh menu", action: #selector(refreshMenu), keyEquivalent: "")
        refresh.target = self
        menu.addItem(refresh)
        let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
        statusItem.button?.title = unread.isEmpty ? "CP" : "CP • \(unread.count)"
    }

    @objc private func openSignal(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: String],
              let symbol = info["symbol"] else { return }
        if let key = info["key"] { unread.remove(key) }
        renderMenu()
        openSymbol(symbol)
    }

    private func openSymbol(_ symbol: String) {
        guard let signal = store.signals.first(where: { $0.symbol == symbol }) else { return }
        unread.subtract(store.signals.filter { $0.symbol == symbol }.map(\.key))
        renderMenu()
        NSWorkspace.shared.open(signal.url)
    }

    @objc private func openDashboard() { NSWorkspace.shared.open(server) }
    @objc private func refreshMenu() { poll() }
    @objc private func quitApp() { NSApplication.shared.terminate(nil) }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let symbol = response.notification.request.content.userInfo["symbol"] as? String
        DispatchQueue.main.async { [weak self] in
            if let symbol { self?.openSymbol(symbol) }
            completionHandler()
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
