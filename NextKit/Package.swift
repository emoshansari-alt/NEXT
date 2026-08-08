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

    // Required, not cosmetic. Without it SwiftPM assumes a very old Apple deployment target
    // (macOS 10.13), where structured concurrency does not exist — so `withTaskGroup` in the
    // storage contract fails to build on macOS while compiling fine on Windows, which has no
    // such floor. iOS 17 is the app's deployment target (DECISIONS.md D-004); macOS is here
    // only because the package is built there by CI and by Xcode.
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],

    products: [
        .library(name: "NextKit", targets: ["NextKit"]),

        // The storage contract, as runnable code. A library rather than test-target code
        // because the implementation it matters most for — the SwiftData store in NextApp —
        // lives in a different target that Tier 1 cannot even compile. Shipping it as a
        // product is what lets both tiers run the identical checks instead of re-deriving
        // them and drifting.
        .library(name: "NextKitTestSupport", targets: ["NextKitTestSupport"])
    ],
    targets: [
        .target(
            name: "NextKit",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .target(
            name: "NextKitTestSupport",
            dependencies: ["NextKit"],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .testTarget(
            name: "NextKitTests",
            dependencies: ["NextKit", "NextKitTestSupport"]
        )
    ]
)
