// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Spokn",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Spokn", targets: ["Spokn"])],
    dependencies: [.package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.15.7", traits: [])],
    targets: [
        .executableTarget(name: "Spokn", dependencies: [.product(name: "FluidAudio", package: "FluidAudio")], path: "native/Sources/Spokn", swiftSettings: [.defaultIsolation(MainActor.self)], linkerSettings: [
            .linkedFramework("AppKit"), .linkedFramework("AVFoundation"),
            .linkedFramework("NaturalLanguage"), .linkedFramework("Carbon")
        ]),
        .testTarget(name: "SpoknTests", dependencies: ["Spokn"], path: "native/Tests/SpoknTests", swiftSettings: [.defaultIsolation(MainActor.self)])
    ]
)
