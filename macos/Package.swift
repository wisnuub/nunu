// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Nunu",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/grpc/grpc-swift-2.git", from: "2.4.4"),
        .package(url: "https://github.com/grpc/grpc-swift-nio-transport.git", from: "2.12.0"),
        .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", from: "2.5.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.39.0"),
    ],
    targets: [
        // Generated from the engine's emulator_controller.proto (see proto/ and scripts/gen-proto.sh)
        .target(
            name: "EmulatorAPI",
            dependencies: [
                .product(name: "GRPCCore", package: "grpc-swift-2"),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ]
        ),
        .executableTarget(
            name: "Nunu",
            dependencies: [
                "EmulatorAPI",
                .product(name: "GRPCCore", package: "grpc-swift-2"),
                .product(name: "GRPCNIOTransportHTTP2", package: "grpc-swift-nio-transport"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("GameController"),
                .linkedFramework("LocalAuthentication"),
            ]
        ),
    ]
)
