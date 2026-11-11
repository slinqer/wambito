// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WambitoNative",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "WambitoNative", targets: ["WambitoNative"]),
    ],
    targets: [
        .target(name: "WambitoNative"),
        .testTarget(name: "WambitoNativeTests", dependencies: ["WambitoNative"]),
    ]
)
