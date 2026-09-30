// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CandlepointMenu",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "CandlepointMenu", targets: ["CandlepointMenu"])],
    targets: [
        .target(name: "SignalCore"),
        .executableTarget(name: "CandlepointMenu", dependencies: ["SignalCore"]),
        .testTarget(name: "SignalCoreTests", dependencies: ["SignalCore"], path: "tests/SignalCoreTests"),
    ]
)
