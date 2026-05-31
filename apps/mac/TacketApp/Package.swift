// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TacketApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "TacketApp", targets: ["TacketApp"]),
        .executable(name: "TacketNativeHost", targets: ["TacketNativeHost"])
    ],
    targets: [
        .executableTarget(name: "TacketApp"),
        .executableTarget(name: "TacketNativeHost")
    ]
)
