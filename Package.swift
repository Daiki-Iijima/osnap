// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "osnap",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "osnap", targets: ["osnap"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "osnap",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
    ]
)
