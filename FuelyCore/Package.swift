// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FuelyCore",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "FuelyCore", targets: ["FuelyCore"]),
    ],
    targets: [
        .target(name: "FuelyCore"),
        .testTarget(name: "FuelyCoreTests", dependencies: ["FuelyCore"]),
    ]
)
