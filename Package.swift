// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MXMenu",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MXMenu",
            path: "Sources/MXMenu",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
