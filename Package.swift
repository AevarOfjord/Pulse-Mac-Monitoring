// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pulse",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Pulse", targets: ["Pulse"]),
               .executable(name: "PulseDiagnostics", targets: ["PulseDiagnostics"])],
    targets: [
        .target(name: "MonitorCore", linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "Pulse", dependencies: ["MonitorCore"]),
        .executableTarget(name: "PulseDiagnostics", dependencies: ["MonitorCore"]),
        .testTarget(name: "MonitorCoreTests", dependencies: ["MonitorCore"])
    ],
    swiftLanguageModes: [.v5]
)
