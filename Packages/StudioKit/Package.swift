// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "StudioKit", platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "StudioFeatures", targets: ["StudioFeatures"])],
    targets: [
        .target(name: "StudioCore"),
        .target(name: "ProviderKit", dependencies: ["StudioCore"]),
        .target(name: "StudioPersistence", dependencies: ["StudioCore", "ProviderKit"]),
        .target(name: "StudioMedia", dependencies: ["StudioCore"]),
        .target(name: "StudioFeatures", dependencies: ["StudioCore", "ProviderKit", "StudioPersistence", "StudioMedia"]),
        .testTarget(name: "StudioCoreTests", dependencies: ["StudioCore"]),
        .testTarget(name: "ProviderKitTests", dependencies: ["ProviderKit"]),
        .testTarget(name: "StudioPersistenceTests", dependencies: ["StudioPersistence", "ProviderKit"])
    ])
