// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VeriCapture",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "VeriCaptureCore",
            targets: ["VeriCaptureCore"]
        )
    ],
    targets: [
        .target(
            name: "VeriCaptureCore",
            path: "Sources",
            sources: [
                "Verification/CryptoVerificationService.swift",
                "Verification/ProofModels.swift"
            ],
            resources: [
                .process("../Resources")
            ]
        ),
        .testTarget(
            name: "VeriCaptureCoreTests",
            dependencies: ["VeriCaptureCore"],
            path: "Tests",
            resources: [
                .process("Fixtures")
            ]
        )
    ]
)
