// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ZoomLiveTranslator",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "ZoomLiveTranslator", targets: ["ZoomLiveTranslator"])],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", exact: "1.1.1"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.7", traits: [])
    ],
    targets: [
        .target(name: "TranslatorCore"),
        .target(name: "LocalRecognition", dependencies: ["TranslatorCore", .product(name: "WhisperKit", package: "argmax-oss-swift"), .product(name: "FluidAudio", package: "FluidAudio")]),
        .executableTarget(name: "RecognitionDiagnostics", dependencies: ["LocalRecognition", "TranslatorCore"], path: "Tools/RecognitionDiagnostics"),
        .executableTarget(name: "ZoomLiveTranslator", dependencies: ["TranslatorCore", "LocalRecognition"]),
        .executableTarget(name: "OllamaDiagnostics", dependencies: ["TranslatorCore"], path: "Tools/OllamaDiagnostics"),
        .testTarget(name: "TranslatorCoreTests", dependencies: ["TranslatorCore"])
    ]
)
