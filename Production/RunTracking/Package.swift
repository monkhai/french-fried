// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RunTracking",
    platforms: [.iOS("26.0"), .macOS(.v14)],
    products: [.library(name: "RunTracking", targets: ["RunTracking"])],
    targets: [
        .target(name: "RunTracking"),
        .testTarget(name: "RunTrackingTests", dependencies: ["RunTracking"])
    ]
)
