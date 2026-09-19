// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "swift-guardian",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-syntax.git",
            from: "510.0.0"
        )
    ],
    targets: [
        .target(
            name: "SwiftGuardianCore",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ],
            path: "Sources/SwiftGuardianCore"
        ),
        .executableTarget(
            name: "swift-guardian",
            dependencies: [
                "SwiftGuardianCore",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ],
            path: "Sources/swift-guardian"
        ),
        .testTarget(
            name: "swift-guardianTests",
            dependencies: [
                "SwiftGuardianCore",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ],
            path: "Tests/swift-guardianTests",
            resources: [.copy("Fixtures")]
        )
    ]
)
