// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QuickMarkCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "QuickMarkCore", targets: ["QuickMarkCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.3.0"),
    ],
    targets: [
        .target(
            name: "QuickMarkCore",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "QuickMarkCoreTests",
            dependencies: ["QuickMarkCore"]
        ),
    ]
)
