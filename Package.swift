// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VieLotusIM",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "VieLotusIM", targets: ["VieLotusIM"]),
        .executable(name: "VieLotusCLI", targets: ["VieLotusCLI"]),
        .library(name: "VieLotusCore", targets: ["VieLotusCore"]),
        .library(name: "VieLotusCAPI", type: .dynamic, targets: ["VieLotusCAPI"]),
    ],
    targets: [
        .target(
            name: "VieLotusCore",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("Cocoa", .when(platforms: [.macOS])),
                .linkedFramework("NaturalLanguage", .when(platforms: [.macOS])),
            ]
        ),
        .target(
            name: "VieLotusCAPI",
            dependencies: ["VieLotusCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "VieLotusTrace",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("Carbon", .when(platforms: [.macOS])),
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
            ]
        ),
        .executableTarget(
            name: "VieLotusCLI",
            dependencies: ["VieLotusCore"],
            resources: [.copy("Resources/test_suite.csv")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "VieLotusIM",
            dependencies: ["VieLotusCore", "VieLotusTrace"],
            exclude: [
                "Info.plist",
                "Resources/AppIcon.icns",
                "Resources/MenuBarTemplate.tiff",
                "Resources/MenuBarTemplate.png",
                "Resources/MenuBarTemplate@2x.png",
                "Resources/vietqr.png",
            ],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("InputMethodKit"),
                .linkedFramework("Carbon"),
            ]
        ),
        .testTarget(
            name: "VieLotusCoreTests",
            dependencies: ["VieLotusCore", "VieLotusTrace", "VieLotusCAPI"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("Cocoa", .when(platforms: [.macOS])),
                .linkedFramework("NaturalLanguage", .when(platforms: [.macOS])),
            ]
        ),
    ]
)
