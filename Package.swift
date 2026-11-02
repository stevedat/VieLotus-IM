// swift-tools-version:6.0
// =============================================================================
// Package.swift — VieLotusIM Public Repo (Open-Core)
// =============================================================================
// This Package.swift links against a prebuilt VieLotusCore.xcframework binary.
// The full source for VieLotusCore is maintained in a private repository.
//
// To build the macOS IMK shell:
//   swift build --product VieLotusIM
//
// To verify prebuilt binary integrity:
//   shasum -a 256 -c Binaries/checksums.sha256
// =============================================================================
import PackageDescription

var products: [Product] = []

var targets: [Target] = [
    // VieLotusCore — prebuilt binary framework (arm64+x86_64 macOS, arm64 iOS)
    .binaryTarget(
        name: "VieLotusCore",
        path: "Frameworks/VieLotusCore.xcframework"
    ),

    // VieLotusTrace — diagnostic trace contracts (MIT, full source)
    .target(
        name: "VieLotusTrace",
        dependencies: [],
        swiftSettings: [.swiftLanguageMode(.v5)]
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
