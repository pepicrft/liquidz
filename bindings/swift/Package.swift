// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

let useLocalArtifactBundle = ProcessInfo.processInfo.environment["LIQUIDZ_USE_LOCAL_ARTIFACT_BUNDLE"] == "1"
let artifactVersion = ProcessInfo.processInfo.environment["LIQUIDZ_ARTIFACT_VERSION"] ?? "VERSION"
let artifactChecksum = ProcessInfo.processInfo.environment["LIQUIDZ_ARTIFACT_CHECKSUM"] ?? "CHECKSUM"

let cliquidzTarget: Target = useLocalArtifactBundle
    ? .binaryTarget(
        name: "CLiquidz",
        path: "CLiquidz.artifactbundle"
    )
    : .binaryTarget(
        name: "CLiquidz",
        url: "https://github.com/pepicrft/liquidz/releases/download/\(artifactVersion)/liquidz.artifactbundle.zip",
        checksum: artifactChecksum
    )

let package = Package(
    name: "Liquidz",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
        .tvOS(.v15),
        .watchOS(.v8),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "Liquidz",
            targets: ["Liquidz"]
        ),
    ],
    targets: [
        cliquidzTarget,
        .target(
            name: "Liquidz",
            dependencies: ["CLiquidz"],
            path: "Sources/Liquidz"
        ),
        .testTarget(
            name: "LiquidzTests",
            dependencies: ["Liquidz"],
            path: "Tests/LiquidzTests"
        ),
    ]
)
