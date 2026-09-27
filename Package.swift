// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "AmountlyRules", products: [.library(name: "AmountlyRules", targets: ["AmountlyRules"])], targets: [
    .target(name: "AmountlyRules", path: "alpha/Core/Reporting"),
    .testTarget(name: "AmountlyRulesTests", dependencies: ["AmountlyRules"], path: "Tests/AmountlyRulesTests")
])
