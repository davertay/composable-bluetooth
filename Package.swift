// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "composable-bluetooth",
    platforms: [
        .iOS(.v15),
        .macOS(.v10_15),
        .tvOS(.v15),
        .watchOS(.v6),
    ],
    products: [
        .library(
            name: "ComposableBluetooth",
            targets: ["ComposableBluetooth"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.15.0"),
        .package(url: "https://github.com/Lision/WKWebViewJavascriptBridge", from: "1.2.3")
    ],
    targets: [
        .target(
            name: "ComposableBluetooth",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "WKWebViewJavascriptBridge", package: "WKWebViewJavascriptBridge")
            ]
        ),
        .testTarget(
            name: "ComposableBluetoothTests",
            dependencies: ["ComposableBluetooth"]
        ),
    ]
)
