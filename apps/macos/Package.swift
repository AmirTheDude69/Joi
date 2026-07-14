// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "JoiMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Joi", targets: ["JoiMac"]),
    ],
    targets: [
        .target(
            name: "MediaRemoteShim",
            path: "Sources/MediaRemoteShim",
            publicHeadersPath: "include",
            cSettings: [.unsafeFlags(["-fblocks"])],
            linkerSettings: [.linkedLibrary("objc")]
        ),
        .executableTarget(
            name: "JoiMac",
            dependencies: ["MediaRemoteShim"],
            path: "Sources/JoiMac"
        ),
    ]
)
