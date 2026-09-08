// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Brim",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Brim", targets: ["Brim"])],
    targets: [
        .target(name: "BrimCore"),
        .executableTarget(name: "Brim", dependencies: ["BrimCore"]),
        .testTarget(name: "BrimCoreTests", dependencies: ["BrimCore"])
    ],
    swiftLanguageModes: [.v5]
)
