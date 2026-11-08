// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenSwitcher",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "OpenSwitcher", targets: ["OpenSwitcher"])
    ],
    targets: [
        .executableTarget(
            name: "OpenSwitcher",
            path: "Sources"
        )
    ]
)
