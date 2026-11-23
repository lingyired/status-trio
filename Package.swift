// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StatusTrio",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "StatusTrioAirPodsHelper", targets: ["StatusTrioAirPodsHelper"]),
        .library(name: "AirPodsAudioContext", type: .dynamic, targets: ["AirPodsAudioContext"]),
        .executable(name: "StatusTrio", targets: ["StatusTrio"]),
        .library(name: "StatusTrioCore", type: .dynamic, targets: ["StatusTrioCore"]),
        .executable(name: "StatusTrioPowerHelper", targets: ["StatusTrioPowerHelper"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0")
    ],
    targets: [
        .executableTarget(name: "StatusTrioAirPodsHelper", linkerSettings: [.linkedFramework("Foundation"), .linkedFramework("CoreAudio"), .linkedFramework("Security")]),
        .target(name: "AirPodsAudioContext", exclude: ["LICENSE"], publicHeadersPath: "include", linkerSettings: [.linkedFramework("CoreFoundation"), .linkedFramework("Security")]),
        .target(
            name: "StatusTrioCore",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                "DDCPrivateAPI",
                "PowerUIPrivateAPI",
                "PowerHelperProtocol"
            ],
            path: "Sources/StatusTrioCore",
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("IOKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreWLAN"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreDisplay"),
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("Network"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SystemConfiguration"),
                // IOReport (private system stub) for estimated CPU cluster frequency.
                .linkedLibrary("IOReport")
            ]
        ),
        // Shared between the app and the privileged daemon so the daemon does
        // not link AppKit, SwiftUI, or Sparkle just to name the XPC protocol.
        .target(
            name: "PowerHelperProtocol",
            path: "Sources/PowerHelperProtocol"
        ),
        // Minimal AppleSMC access for the legacy charge limiter. Linked only
        // into the root helper; the write allowlist lives inside the bridge.
        .target(
            name: "SMCPrivateAPI",
            path: "Sources/SMCPrivateAPI",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "StatusTrioPowerHelper",
            dependencies: ["PowerHelperProtocol", "SMCPrivateAPI"],
            path: "Sources/StatusTrioPowerHelper",
            linkerSettings: [
                .linkedFramework("Security"),
                .linkedFramework("IOKit")
            ]
        ),
        .target(
            name: "DDCPrivateAPI",
            path: "Sources/DDCPrivateAPI",
            publicHeadersPath: "include"
        ),
        .target(
            name: "PowerUIPrivateAPI",
            path: "Sources/PowerUIPrivateAPI",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "StatusTrio",
            dependencies: ["StatusTrioCore"],
            path: "Sources/StatusTrio"
        ),
        .testTarget(
            name: "StatusTrioCoreTests",
            dependencies: ["StatusTrioCore", "PowerHelperProtocol"],
            path: "Tests/StatusTrioCoreTests"
        ),
        // The daemon owns its own lifetime, so its idle policy is exercised
        // directly: the executable target is linked into this bundle, and the
        // top-level code in main.swift never runs here.
        .testTarget(
            name: "StatusTrioPowerHelperTests",
            dependencies: ["StatusTrioPowerHelper", "SMCPrivateAPI"],
            path: "Tests/StatusTrioPowerHelperTests"
        )
    ]
)
