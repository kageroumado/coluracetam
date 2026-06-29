// swift-tools-version: 6.3
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    // Module is MainActor-isolated by default (SE-0466) — this is a UI module.
    .defaultIsolation(MainActor.self),
    // Nonisolated async functions run on the caller's executor (SE-0461),
    // matching the rest of the suite.
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let package = Package(
    name: "coluracetam-kit",
    platforms: [
        .macOS("26.0"),
    ],
    products: [
        .library(name: "ColuracetamKit", targets: ["ColuracetamKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/textual", from: "0.5.0"),
    ],
    targets: [
        .target(
            name: "ColuracetamKit",
            dependencies: [
                .product(name: "Textual", package: "textual"),
            ],
            swiftSettings: swiftSettings,
        ),
        .testTarget(
            name: "ColuracetamKitTests",
            dependencies: ["ColuracetamKit"],
            swiftSettings: swiftSettings,
        ),
    ],
    swiftLanguageModes: [.v6],
)
