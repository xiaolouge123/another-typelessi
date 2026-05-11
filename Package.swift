// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "another-typelessi",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AnotherTypeless", targets: ["AnotherTypeless"])
    ],
    targets: [
        .executableTarget(name: "AnotherTypeless")
    ]
)
