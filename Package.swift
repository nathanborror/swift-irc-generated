// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-irc3",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "IRC3", targets: ["IRC3"]),
    ],
    targets: [
        .target(name: "IRC3"),
        .testTarget(name: "IRC3Tests", dependencies: ["IRC3"]),
    ]
)
