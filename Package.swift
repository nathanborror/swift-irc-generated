// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "swift-irc",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "IRC", targets: ["IRC"])
    ],
    targets: [
        .target(name: "IRC"),
        .testTarget(name: "IRCTests", dependencies: ["IRC"]),
    ]
)
