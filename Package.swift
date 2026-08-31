// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "GetKbd",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "getkbd", targets: ["GetKbd"])
    ],
    targets: [
        .executableTarget(
            name: "GetKbd",
            path: "Sources/GetKbd",
            exclude: ["Resources"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ColorSync"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(
            name: "GetKbdTests",
            dependencies: ["GetKbd"],
            path: "Tests/GetKbdTests"
        )
    ]
)
