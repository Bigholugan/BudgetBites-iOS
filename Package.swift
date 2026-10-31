// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BudgetBites",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "BudgetBites",
            targets: ["BudgetBites"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "BudgetBites",
            dependencies: [],
            path: "Sources/BudgetBites",
            resources: [
                .process("Resources/Assets.xcassets"),
                .copy("Resources/www"),
                .copy("Resources/Info.plist")
            ]
        ),
        .testTarget(
            name: "BudgetBitesTests",
            dependencies: ["BudgetBites"],
            path: "Tests/BudgetBitesTests"
        )
    ]
)
