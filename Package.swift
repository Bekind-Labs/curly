// swift-tools-version:5.9
import PackageDescription

// The app target is only declared when the manifest is evaluated on macOS.
// CurlKit is pure Swift with no UI imports, so `swift test` works anywhere
// (including Linux CI); the SwiftUI app only exists where it can be built.
var products: [Product] = [
    .library(name: "CurlKit", targets: ["CurlKit"])
]

var targets: [Target] = [
    .target(name: "CurlKit"),
    .testTarget(name: "CurlKitTests", dependencies: ["CurlKit"]),
]

#if os(macOS)
products.append(.executable(name: "curly", targets: ["curly"]))
targets.append(
    .executableTarget(
        name: "curly",
        dependencies: ["CurlKit"],
        resources: [.process("Resources")]
    )
)
#endif

let package = Package(
    name: "curly",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
