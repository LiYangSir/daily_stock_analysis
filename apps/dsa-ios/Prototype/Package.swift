// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DSAPrototype",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DSAPrototype", targets: ["DSAPrototype"])
    ],
    targets: [
        .target(
            name: "DSAPrototype",
            path: "Sources/DSAPrototype"
        )
    ]
)
