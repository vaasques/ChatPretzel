// swift-tools-version: 5.9
import PackageDescription

var products: [Product] = [.library(name: "ChatDeskCore", targets: ["ChatDeskCore"])]
var targets: [Target] = [
    .target(name: "ChatDeskCore"),
    .testTarget(name: "ChatDeskCoreTests", dependencies: ["ChatDeskCore"])
]
#if os(macOS)
products.append(.executable(name: "ChatDesk", targets: ["ChatDeskApp"]))
targets += [
    .target(name: "ChatDeskMac", dependencies: ["ChatDeskCore"],
            resources: [.copy("Resources")],
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("WebKit"),
                             .linkedFramework("Carbon"), .linkedFramework("UniformTypeIdentifiers")]),
    .executableTarget(name: "ChatDeskApp", dependencies: ["ChatDeskMac"]),
    .testTarget(name: "ChatDeskMacTests", dependencies: ["ChatDeskMac", "ChatDeskCore"])
]
#endif
let package = Package(name: "ChatDesk", platforms: [.macOS(.v13)],
                      products: products, dependencies: [], targets: targets,
                      swiftLanguageVersions: [.v5])
