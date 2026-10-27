// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RCamera",
    products: [
        .library(name: "CameraCore", targets: ["CameraCore"]),
        .executable(name: "luttool", targets: ["luttool"]),
    ],
    targets: [
        .target(name: "CameraCore"),
        .executableTarget(name: "luttool", dependencies: ["CameraCore"]),
        .testTarget(name: "CameraCoreTests", dependencies: ["CameraCore"]),
    ]
)
