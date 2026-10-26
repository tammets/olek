// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Olek",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Olek", targets: ["Olek"]),
    ],
    targets: [
        .target(
            name: "OlekCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "Olek",
            dependencies: ["OlekCore"]
        ),
        .testTarget(
            name: "OlekCoreTests",
            dependencies: ["OlekCore"]
        ),
    ]
)
