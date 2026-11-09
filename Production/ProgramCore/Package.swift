// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ProgramCore",
    platforms: [.iOS("26.0")],
    products: [.library(name: "ProgramCore", targets: ["ProgramCore"])],
    targets: [
        .target(name: "ProgramCore"),
        .testTarget(name: "ProgramCoreTests", dependencies: ["ProgramCore"])
    ]
)
