import UIKit
import XCTest

/// Forces the simulator's appearance and waits for it to land.
///
/// The wait is the point. Setting the appearance and launching in the same breath does not
/// reliably apply to the app that comes up: the first capture of the App Store set asked for dark
/// immediately before `launch()` and produced a light frame, with every CI step green.
@MainActor
func forceAppearance(_ appearance: XCUIDevice.Appearance) {
    XCUIDevice.shared.appearance = appearance
    _ = XCTWaiter().wait(for: [XCTestExpectation(description: "appearance")], timeout: 1.5)
}

/// The mean brightness of a captured screen, 0 (black) to 1 (white).
///
/// There is no API that reports whether an appearance change actually took, and the failure is
/// invisible to everything else: NEXT's palette clears 4.5:1 in **both** appearances, so a dark
/// audit that quietly ran in light mode passes and reports nothing, and a light screenshot in a
/// set that promises dark mode looks fine until someone opens the app. Measuring the pixels is
/// the only check that cannot be fooled.
@MainActor
func meanBrightness(of image: UIImage) -> CGFloat {
    guard let source = image.cgImage else { return 1 }

    // Averaged by drawing the whole screen into a single pixel: exact, and cheap enough to run
    // on every captured frame. The buffer is owned here rather than borrowed from an array,
    // because the context writes into it after any `withUnsafeMutableBytes` closure would end.
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4)
    buffer.initialize(repeating: 0, count: 4)
    defer { buffer.deallocate() }

    guard let context = CGContext(
        data: buffer,
        width: 1, height: 1,
        bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return 1 }

    context.interpolationQuality = .medium
    context.draw(source, in: CGRect(x: 0, y: 0, width: 1, height: 1))

    let r = CGFloat(buffer[0]) / 255
    let g = CGFloat(buffer[1]) / 255
    let b = CGFloat(buffer[2]) / 255
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
}
