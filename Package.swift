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
        .library(name: "VieLotusCore", targets: ["VieLotusCore"])
    ],
    targets: [
        .target(
            name: "VieLotusCore",
            dependencies: [],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("NaturalLanguage"),
            ]
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
            dependencies: ["VieLotusCore"],
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
        .testTarget(
            name: "VieLotusCoreTests",
            dependencies: ["VieLotusCore"],
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
