// swift-tools-version: 6.2

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let package = Package(
    name: "SmartPrompter",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "StagePrompterCore", targets: ["StagePrompterCore"]),
        .executable(name: "SmartPrompter", targets: ["StagePrompterApp"]),
    ],
    targets: [
        .target(
            name: "StagePrompterCore",
            path: "Sources/StagePrompterCore",
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "StagePrompterApp",
            dependencies: ["StagePrompterCore"],
            path: "Sources/StagePrompterApp",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "StagePrompterCoreTests",
            dependencies: ["StagePrompterCore"],
            path: "Tests/StagePrompterCoreTests",
            swiftSettings: swiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
