// swift-tools-version:6.3
import PackageDescription

let package = Package(
    name: "TorManager",
    defaultLocalization: "en",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "TorManager-iOS", targets: ["TorManager-iOS"]),
        .library(name: "TorManager-iOS-UI", targets: ["TorManager-iOS-UI"]),
        .library(name: "TorManager-macOS", targets: ["TorManager-macOS"]),
    ],
    dependencies: [
        .package(url: "https://github.com/tladesignz/IPtProxyUI-ios.git", from: "6.1.0"),
        .package(url: "https://github.com/iCepa/Tor.framework.git", from: "409.16.1"),
        .package(url: "https://github.com/guardianproject/orbotkit.git", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "TorManager-Shared",
            dependencies: [
                .product(name: "CTor", package: "tor.framework"),
            ],
            packageAccess: false,
        ),
        .target(
            name: "TorManager-iOS",
            dependencies: [
                "TorManager-Shared",
                .product(name: "IPtProxyUI-iOS-AppEx", package: "iptproxyui-ios"),
                .product(name: "OrbotKit", package: "orbotkit"),
            ],
        ),
        .target(
            name: "TorManager-iOS-UI",
            dependencies: [
                "TorManager-iOS",
                .product(name: "IPtProxyUI-iOS", package: "iptproxyui-ios"),
            ],
            resources: [
                .process("Resources")
            ],
        ),
        .target(
            name: "TorManager-macOS",
            dependencies: [
                "TorManager-Shared",
                .product(name: "IPtProxyUI-macOS", package: "iptproxyui-ios"),
            ],
        ),
    ],
    swiftLanguageModes: [.v5]
)
