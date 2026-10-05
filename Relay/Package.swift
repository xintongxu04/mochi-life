// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MochiRelay",
    platforms: [
        .macOS(.v15),
        // So the Mochi Life app can later share RelayCore's message types.
        .iOS(.v18),
    ],
    products: [
        .executable(name: "mochi-relay", targets: ["mochi-relay"]),
        .library(name: "RelayCore", targets: ["RelayCore"]),
    ],
    targets: [
        .target(name: "RelayCore"),
        .executableTarget(name: "mochi-relay", dependencies: ["RelayCore"]),
    ]
)
