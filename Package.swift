// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "HermesDesktop",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "HermesDesktop",
            targets: ["HermesDesktop"]
        )
    ],
    dependencies: [
        .package(path: "Vendor/SwiftTerm"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.5.0")
    ],
    targets: [
        .executableTarget(
            name: "HermesDesktop",
            dependencies: [
                .product(
                    name: "SwiftTerm",
                    package: "SwiftTerm",
                    condition: .when(platforms: [.macOS])
                ),
                .product(name: "Crypto", package: "swift-crypto")
            ],
            path: "Sources/HermesDesktop",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "HermesDesktopTests",
            dependencies: ["HermesDesktop"],
            path: "Tests/HermesDesktopTests"
        )
    ]
)
