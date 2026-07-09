// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VoiceSlave",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "VoiceSlave", targets: ["VoiceSlave"]),
        .executable(name: "VoiceSlaveCoreTestRunner", targets: ["VoiceSlaveCoreTestRunner"]),
        .library(name: "VoiceSlaveCore", targets: ["VoiceSlaveCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0")
    ],
    targets: [
        .target(
            name: "VoiceSlaveCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "VoiceSlave",
            dependencies: [
                "VoiceSlaveCore",
                .product(name: "WhisperKit", package: "WhisperKit")
            ]
        ),
        .executableTarget(
            name: "VoiceSlaveCoreTestRunner",
            dependencies: ["VoiceSlaveCore"]
        )
    ]
)
