// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DailyGoal",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "DailyGoal", path: "Sources/DailyGoal")
    ]
)
