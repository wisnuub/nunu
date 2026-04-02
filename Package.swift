// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "nunu",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "nunu",
            path: "Sources/nunu",
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals")
            ]
        )
    ]
)
