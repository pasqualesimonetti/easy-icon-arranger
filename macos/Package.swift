// swift-tools-version: 6.2
// Native macOS app (SwiftUI). The device engine is Go, linked as a static
// library (Vendor/libeia.a, built by scripts/build.sh).
import Foundation
import PackageDescription

let vendor = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Vendor").path

let package = Package(
    name: "EasyIconArranger",
    platforms: [.macOS(.v26)],
    targets: [
        .systemLibrary(name: "CEIA", path: "Sources/CEIA"),
        .executableTarget(
            name: "EasyIconArranger",
            dependencies: ["CEIA"],
            swiftSettings: [.swiftLanguageMode(.v6)],
            linkerSettings: [
                .unsafeFlags(["-L", vendor]),
                .linkedLibrary("eia"),
                .linkedLibrary("resolv"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("Security"),
                .linkedFramework("AppKit"),
            ]
        ),
    ]
)
