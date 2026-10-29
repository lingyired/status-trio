// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StatusTrio",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "StatusTrio", targets: ["StatusTrio"]),
        .executable(name: "StatusTrioPowerHelper", targets: ["StatusTrioPowerHelper"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0")
    ],
    targets: [
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
                .linkedFramework("SystemConfiguration")
            ]
        ),
        // Shared between the app and the privileged daemon so the daemon does
        // not link AppKit, SwiftUI, or Sparkle just to name the XPC protocol.
        .target(
            name: "PowerHelperProtocol",
            path: "Sources/PowerHelperProtocol"
        ),
        .executableTarget(
            name: "StatusTrioPowerHelper",
            dependencies: ["PowerHelperProtocol"],
            path: "Sources/StatusTrioPowerHelper",
            linkerSettings: [
                .linkedFramework("Security")
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
            dependencies: ["StatusTrioPowerHelper"],
            path: "Tests/StatusTrioPowerHelperTests"
        )
    ]
)
