// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TempCheck",
    platforms: [.macOS(.v12)],
    products: [.executable(name: "TempCheck", targets: ["TempCheck"])],
    targets: [
        .target(name: "CSensors", linkerSettings: [.linkedFramework("IOKit")]),
        .target(name: "TempCheckCore", dependencies: ["CSensors"]),
        .executableTarget(name: "TempCheck", dependencies: ["TempCheckCore"]),
        .testTarget(name: "TempCheckCoreTests", dependencies: ["TempCheckCore", "CSensors"]),
        .testTarget(name: "TempCheckAppTests", dependencies: ["TempCheck", "TempCheckCore"])
    ]
)
