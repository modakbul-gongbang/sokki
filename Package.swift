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
    targets: [
        .target(
            name: "VoiceSlaveCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "VoiceSlave",
            dependencies: ["VoiceSlaveCore"]
        ),
        .executableTarget(
            name: "VoiceSlaveCoreTestRunner",
            dependencies: ["VoiceSlaveCore"]
        )
    ]
)
