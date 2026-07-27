// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TokenSignal",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TokenSignal", targets: ["TokenSignal"])
    ],
    targets: [
        .target(name: "TokenSignalCore"),
        .executableTarget(
            name: "TokenSignal",
            dependencies: ["TokenSignalCore"]
        ),
        .testTarget(
            name: "TokenSignalCoreTests",
            dependencies: ["TokenSignalCore"]
        )
    ]
)
