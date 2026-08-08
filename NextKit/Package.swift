// swift-tools-version: 6.0
//
// NextKit — the pure-Swift core of NEXT.
//
// This package must depend on nothing but Foundation. No SwiftUI, no UIKit, no SwiftData,
// no WidgetKit, no StoreKit, no UserNotifications, no third-party packages.
// See ARCHITECTURE.md §2 and DECISIONS.md D-002. CI enforces this.
//
// Because of that constraint this package compiles and its tests genuinely run on
// Windows and Linux as well as macOS, which is what makes Tier 1 verification real.

import PackageDescription

let package = Package(
    name: "NextKit",
    products: [
        .library(name: "NextKit", targets: ["NextKit"])
    ],
    targets: [
        .target(
            name: "NextKit",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .testTarget(
            name: "NextKitTests",
            dependencies: ["NextKit"]
        )
    ]
)
