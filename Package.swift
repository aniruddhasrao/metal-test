// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MetalTest",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "ShaderTypes",
            path: "Sources/ShaderTypes",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "MetalTest",
            dependencies: ["ShaderTypes"],
            path: "Sources/MetalTest"
        ),
    ]
)
