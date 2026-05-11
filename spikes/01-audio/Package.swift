// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "audio_test",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "audio_test", path: ".", sources: ["audio_test.swift"])
    ]
)
