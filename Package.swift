// swift-tools-version:5.8
import PackageDescription

// The pure timer logic (config, countdown state machine, formatting, history) lives in its own
// module so it builds and tests anywhere Swift runs (`swift test`, including Linux CI), and the
// Xcode project consumes it as a local package.
let package = Package(
    name: "TimerCore",
    platforms: [.macOS("14.0")],
    products: [
        .library(name: "TimerCore", targets: ["TimerCore"]),
    ],
    targets: [
        .target(name: "TimerCore", path: "Sources/Engine"),
        .testTarget(name: "TimerEngineTests", dependencies: ["TimerCore"], path: "Tests"),
    ]
)
