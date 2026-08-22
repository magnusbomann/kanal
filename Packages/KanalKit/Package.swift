// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KanalKit",
    // Required for a package to localize at all. Without it, string catalogs
    // in the package are never consulted.
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .tvOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "KanalCore", targets: ["KanalCore"]),
        .library(name: "KanalUI", targets: ["KanalUI"]),
    ],
    targets: [
        .target(
            name: "KanalCore",
            resources: [.copy("Resources/en.lproj"), .copy("Resources/nb.lproj")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "KanalUI",
            dependencies: ["KanalCore"],
            resources: [.copy("Resources/en.lproj"), .copy("Resources/nb.lproj")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "KanalCoreTests",
            dependencies: ["KanalCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
