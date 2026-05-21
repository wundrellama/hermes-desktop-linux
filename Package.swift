// swift-tools-version: 6.1

import PackageDescription

// On Linux we build only the headless core (Models + Services + Utilities +
// Resources + Platform/Linux) as a static library. The C++/Qt6 UI (Phase 4+)
// will link against libHermesCore.a via a C ABI bridge. On macOS we still
// build the full SwiftUI executable.
//
// The fork point lives entirely in this manifest so `Sources/HermesDesktop/`
// stays the same tree as upstream, which keeps `git pull upstream main`
// merges clean.
#if os(Linux)
let mainTarget: Target = .target(
    name: "HermesDesktop",
    dependencies: [
        .product(name: "Crypto", package: "swift-crypto")
    ],
    path: "Sources/HermesDesktop",
    exclude: [
        // SwiftUI/AppKit application layer — replaced by C++/Qt6/Kirigami on Linux.
        "App",
        "Views",
        // AppKit-coupled NSView host + Combine ObservableObject classes —
        // the Linux terminal uses QTermWidget via C++.
        "Services/Terminal",
        // Uses Combine's @Published; deferred until the Observation-macro
        // refactor lands (separate session). The C++ UI talks to a slimmer
        // Swift façade we'll add when the FFI exports go in.
        "Services/Storage/ConnectionStore.swift",
        // Terminal-tab UI state classes (ObservableObject / @Published).
        // Live in Models/ for historical reasons; conceptually part of the
        // macOS Views layer. Linux replaces with C++/Qt models.
        "Models/SessionTUIModels.swift",
        "Models/TerminalTabModel.swift"
    ],
    resources: [
        .process("Resources")
    ]
)
let mainProduct: Product = .library(
    name: "HermesCore",
    type: .static,
    targets: ["HermesDesktop"]
)
// Tests that depend on the excluded sources also drop on Linux.
let testExcludes: [String] = [
    "ConnectionStoreTests.swift",           // ConnectionStore (Combine)
    "WorkflowPersistenceTests.swift",       // ConnectionStore
    "TerminalWorkspaceStoreTests.swift",    // Services/Terminal/
    "TerminalInputSequenceTests.swift",     // type defined in TerminalViewHost.swift
    "AppSectionTests.swift",                // tests AppSection.navigationShortcutKey (canImport(SwiftUI))
    "AppStateUpdateCheckTests.swift"        // AppState (App/, excluded)
]
#else
let mainTarget: Target = .executableTarget(
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
)
let mainProduct: Product = .executable(
    name: "HermesDesktop",
    targets: ["HermesDesktop"]
)
let testExcludes: [String] = []
#endif

// SwiftTerm only ships a macOS terminal host today; vendoring it on Linux
// produces "dependency not used by any target" warnings on every build.
// Gate the package-level dependency at manifest evaluation time.
#if os(Linux)
let packageDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/apple/swift-crypto.git", from: "3.5.0")
]
#else
let packageDependencies: [Package.Dependency] = [
    .package(path: "Vendor/SwiftTerm"),
    .package(url: "https://github.com/apple/swift-crypto.git", from: "3.5.0")
]
#endif

let package = Package(
    name: "HermesDesktop",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        mainProduct
    ],
    dependencies: packageDependencies,
    targets: [
        mainTarget,
        .testTarget(
            name: "HermesDesktopTests",
            dependencies: [
                "HermesDesktop",
                .product(name: "Crypto", package: "swift-crypto")
            ],
            path: "Tests/HermesDesktopTests",
            exclude: testExcludes
        )
    ]
)
