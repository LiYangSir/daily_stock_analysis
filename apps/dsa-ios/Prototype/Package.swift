// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DSAPrototype",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DSAPrototype", targets: ["DSAPrototype"])
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.0")
    ],
    targets: [
        .target(
            name: "DSAPrototype",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui")
            ],
            path: "Sources/DSAPrototype"
        )
    ]
)
