// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "AmountlyRules", platforms: [.macOS(.v13)], products: [.library(name: "AmountlyRules", targets: ["AmountlyRules"])], targets: [
    .target(name: "AmountlyAI", path: "alpha/Core/AI"),
    .testTarget(name: "AmountlyAITests", dependencies: ["AmountlyAI"], path: "Tests/AmountlyAITests"),
    .target(name: "AmountlyRules", path: "alpha/Core/Reporting"),
    .testTarget(name: "AmountlyRulesTests", dependencies: ["AmountlyRules"], path: "Tests/AmountlyRulesTests")
])
