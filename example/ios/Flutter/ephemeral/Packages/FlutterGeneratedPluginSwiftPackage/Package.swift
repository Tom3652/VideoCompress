// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
// Generated file. Do not edit.
//

import PackageDescription

let package = Package(
    name: "FlutterGeneratedPluginSwiftPackage",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "FlutterGeneratedPluginSwiftPackage", type: .static, targets: ["FlutterGeneratedPluginSwiftPackage"])
    ],
    dependencies: [
        .package(name: "image_picker_ios", path: "../.packages/image_picker_ios-0.8.13+6"),
        .package(name: "video_compress", path: "../.packages/VideoCompress"),
        .package(name: "video_player_avfoundation", path: "../.packages/video_player_avfoundation-2.11.0"),
        .package(name: "FlutterFramework", path: "../.packages/FlutterFramework")
    ],
    targets: [
        .target(
            name: "FlutterGeneratedPluginSwiftPackage",
            dependencies: [
                .product(name: "image-picker-ios", package: "image_picker_ios"),
                .product(name: "video-compress", package: "video_compress"),
                .product(name: "video-player-avfoundation", package: "video_player_avfoundation"),
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)
