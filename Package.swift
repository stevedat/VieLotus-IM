// swift-tools-version:6.0
// =============================================================================
// Package.swift — VieLotusIM Public Repo (Open-Core)
// =============================================================================
// This Package.swift resolves VieLotusCore.xcframework via SwiftPM remote
// binaryTarget from GitHub Releases with built-in SHA-256 verification.
// Zero binary blobs are stored in the Git source tree.
//
// To build the macOS IMK shell:
//   swift build --product VieLotusIM
//
// To compute/verify XCFramework zip checksum manually:
//   swift package compute-checksum VieLotusCore.xcframework.zip
// =============================================================================
import PackageDescription

var products: [Product] = []

var targets: [Target] = [
    // VieLotusCore — remote prebuilt binary framework (arm64+x86_64 macOS, arm64 iOS)
    .binaryTarget(
        name: "VieLotusCore",
        url: "https://github.com/stevedat/VieLotus-IM/releases/download/v2.0.2/VieLotusCore.xcframework.zip",
        checksum: "27f1f92910fca00e5526b9872d655127d5b7ca69d8d70ead4756c08ea26131e7"
    ),

    // VieLotusTrace — diagnostic trace contracts (MIT, full source)
    .target(
        name: "VieLotusTrace",
        dependencies: [],
        swiftSettings: [.swiftLanguageMode(.v5)],
        linkerSettings: [
            .linkedFramework("Carbon", .when(platforms: [.macOS])),
        ]
    ),
]

#if os(macOS)
products.append(.executable(name: "VieLotusIM", targets: ["VieLotusIM"]))

targets.append(
    // VieLotusIM — macOS InputMethodKit shell (MIT, full source)
    .executableTarget(
        name: "VieLotusIM",
        dependencies: ["VieLotusCore", "VieLotusTrace"],
        exclude: [
            "Info.plist",
            "Resources/AppIcon.icns",
            "Resources/MenuBarTemplate.tiff",
            "Resources/MenuBarTemplate.png",
            "Resources/MenuBarTemplate@2x.png",
            "Resources/vietqr.png"
        ],
        swiftSettings: [
            .swiftLanguageMode(.v5),
        ],
        linkerSettings: [
            .linkedFramework("Cocoa"),
            .linkedFramework("InputMethodKit"),
            .linkedFramework("Carbon"),
        ]
    )
)
#endif

let package = Package(
    name: "VietLotusIM",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: products,
    targets: targets
)
