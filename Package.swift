// swift-tools-version: 6.0
// Command-line-only SwiftPM manifest, consumed by build-app.sh.
//
// Why it exists: `xcodebuild` resolves SwiftPM packages by re-entering
// `sandbox-exec`, which fails inside an already-sandboxed process. SwiftPM's own
// CLI supports `--disable-sandbox`, so this manifest gives the command-line build
// a path that does not depend on Xcode.
//
// The Xcode project (Prizm/Prizm.xcodeproj) remains the source of truth for
// release builds; keep the two in sync when targets or settings change.

import PackageDescription

let package = Package(
    name: "Prizm",
    platforms: [
        .macOS("26.0")
    ],
    dependencies: [
        .package(path: "LocalPackages/Argon2Swift")
    ],
    targets: [
        .executableTarget(
            name: "Prizm",
            dependencies: [
                .product(name: "Argon2Swift", package: "Argon2Swift")
            ],
            path: "Prizm",
            exclude: [
                "Prizm",
                "PrizmTests",
                "UITests",
                "Prizm.xcodeproj",
                "LocalConfig.xcconfig",
                "LocalConfig.xcconfig.template",
                "PrizmTests.xctestplan",
                // Localizations are copied into Contents/Resources by build-app.sh so
                // that Bundle.main finds them. Routing them through SwiftPM would put
                // them in Prizm_Prizm.bundle, where Bundle.main lookups miss them.
                "Resources/en.lproj",
                "Resources/zh-Hans.lproj"
            ],
            sources: [
                "App",
                "Domain",
                "Data",
                "Presentation"
            ],
            resources: [
                .copy("Resources/eff-large-wordlist.txt")
            ],
            swiftSettings: [
                .unsafeFlags([
                    "-default-isolation", "MainActor",
                    "-enable-upcoming-feature", "NonisolatedNonsendingByDefault",
                    // `InferSendableFromCaptures` is on by default in Swift 6; listing it
                    // only produces an "already enabled" warning.
                    "-enable-upcoming-feature", "MemberImportVisibility"
                ])
            ]
        )
    ]
)
