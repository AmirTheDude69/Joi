// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "JoiMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Joi", targets: ["JoiMac"]),
    ],
    targets: [
        .executableTarget(
            name: "JoiMac",
            path: "Sources/JoiMac"
        ),
    ]
)
