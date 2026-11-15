// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LilliputKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LilliputKit", targets: ["LilliputKit"]),
        .executable(name: "lilliput", targets: ["lilliput"]),
        .executable(name: "MonitorControl", targets: ["MonitorControl"]),
    ],
    targets: [
        .target(name: "LilliputKit"),
        .executableTarget(name: "lilliput", dependencies: ["LilliputKit"]),
        .executableTarget(name: "MonitorControl", dependencies: ["LilliputKit"]),
        .testTarget(name: "LilliputKitTests", dependencies: ["LilliputKit"]),
    ]
)
