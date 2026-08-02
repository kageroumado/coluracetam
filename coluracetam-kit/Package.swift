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
    targets: [
        // Static Rust library (C ABI over firecrawl/pdf-inspector).
        // Rebuild with ../coluracetam-pdf/build-xcframework.sh.
        .binaryTarget(
            name: "ColuracetamPDFCore",
            path: "Artifacts/ColuracetamPDF.xcframework",
        ),
        .target(
            name: "ColuracetamKit",
            dependencies: ["ColuracetamPDFCore"],
            resources: [
                // pdf.js binary CMaps (Adobe CMap resources, BSD-licensed —
                // LICENSE ships inside the folder). Needed for CID/CJK text
                // extraction; PDFImporter points the core here on first use.
                .copy("Resources/bcmaps"),
            ],
            swiftSettings: swiftSettings,
        ),
        .testTarget(
            name: "ColuracetamKitTests",
            dependencies: ["ColuracetamKit"],
            resources: [
                .copy("Fixtures"),
            ],
            swiftSettings: swiftSettings,
        ),
    ],
    swiftLanguageModes: [.v6],
)
