// swift-tools-version: 5.9
import Foundation
import PackageDescription

let infoPlistPath = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Sources/Browsair/Resources/Info.plist")
    .path

let package = Package(
    name: "Browsair",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Browsair",
            path: "Sources/Browsair",
            exclude: [
                "Resources/Info.plist",
                "Resources/Engine/.gitkeep",
            ],
            resources: [
                .copy("Resources/Engine"),
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"]),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", infoPlistPath,
                ]),
            ]
        ),
    ]
)
