// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AppleSignIn",
    platforms: [.iOS("26.0"), .macOS(.v13)],
    products: [.library(name: "AppleSignIn", targets: ["AppleSignIn"])],
    targets: [
        .target(name: "AppleSignIn"),
        .testTarget(name: "AppleSignInTests", dependencies: ["AppleSignIn"])
    ]
)
