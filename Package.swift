// swift-tools-version: 6.0

import PackageDescription

// The TypeWhisper SDK is not a package dependency: the plugin must link the
// SDK framework shipped inside TypeWhisper.app, otherwise the host cannot cast
// the principal class to its own protocols. scripts/build.sh emits the SDK
// interface into .build/sdk from the matching TypeWhisper tag first.
let sdkModuleDir = ".build/sdk"
let hostFrameworks = "/Applications/TypeWhisper.app/Contents/Frameworks"

let package = Package(
    name: "GeminiTranscribator",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GeminiTranscribator", type: .dynamic, targets: ["GeminiTranscribatorPlugin"]),
    ],
    targets: [
        .target(name: "GeminiTranscribatorCore"),
        .target(
            name: "GeminiTranscribatorPlugin",
            dependencies: ["GeminiTranscribatorCore"],
            swiftSettings: [.unsafeFlags(["-I", sdkModuleDir])],
            linkerSettings: [
                .unsafeFlags([
                    "-F", hostFrameworks,
                    "-framework", "TypeWhisperPluginSDK",
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                ]),
            ]
        ),
        .testTarget(name: "GeminiTranscribatorCoreTests", dependencies: ["GeminiTranscribatorCore"]),
    ]
)
