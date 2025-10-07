// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-irc-generated",
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
        .executableTarget(name: "SimpleBot", dependencies: ["IRC"], path: "Examples/SimpleBot"),
    ]
)
