// swift-tools-version:6.0
import PackageDescription
import Foundation

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let frameworksPath = URL(fileURLWithPath: packageRoot)
    .appendingPathComponent("Frameworks").path

let package = Package(
    name: "VietLotusIM",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "VieLotusIM", targets: ["VieLotusIM"]),
        .executable(name: "VieLotusCLI", targets: ["VieLotusCLI"]),
        .executable(name: "VieLotusLab", targets: ["VieLotusLab"]),
        .library(name: "VieLotusCore", targets: ["VieLotusCore"])
    ],
    targets: [
        .target(
            name: "VieLotusCore",
            dependencies: [],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("NaturalLanguage"),
            ]
        ),
        .target(
            name: "VieLotusTrace",
            dependencies: [],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "VieLotusCLI",
            dependencies: ["VieLotusCore"],
            resources: [.copy("Resources/test_suite.csv")],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .linkedFramework("Cocoa"),
            ]
        ),
        .executableTarget(
            name: "VieLotusIM",
            dependencies: ["VieLotusCore", "VieLotusTrace"],
            exclude: ["Info.plist", "Resources/AppIcon.icns"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("InputMethodKit"),
                .linkedFramework("Carbon"),
            ]
        ),
        .executableTarget(
            name: "VieLotusLab",
            dependencies: ["VieLotusCore", "VieLotusTrace"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("SwiftUI"),
            ]
        ),
        .testTarget(
            name: "VieLotusCoreTests",
            dependencies: ["VieLotusCore", "VieLotusTrace"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("NaturalLanguage"),
            ]
        ),
    ]
)
