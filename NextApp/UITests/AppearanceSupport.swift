import UIKit
import XCTest

// `forceAppearance` used to live here and is gone. Setting `XCUIDevice.shared.appearance` did
// not take effect on this runner even with a wait: the check below measured 0.81 — fully light —
// on a screen that had just asked for dark. NEXT's own Dark mode setting is both what users have
// and what actually works, so every test drives that instead.

/// The side of the grid a screen is averaged over before its brightness is computed.
///
/// It used to be 1 — the whole screen drawn into a single pixel. That was cheap and it was also
/// one of the two suspects `AppearanceAvailability` named, because Core Graphics does not promise
/// a box filter over three million pixels at a reduction that extreme, and a measurement nobody
/// trusts cannot settle an argument. A 32 × 32 grid is still one draw call and it is an average
/// no one has to take on faith.
private let brightnessGrid = 32

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

    let side = brightnessGrid
    let count = side * side
    // The buffer is owned here rather than borrowed from an array, because the context writes
    // into it after any `withUnsafeMutableBytes` closure would end.
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: count * 4)
    buffer.initialize(repeating: 0, count: count * 4)
    defer { buffer.deallocate() }

    guard let context = CGContext(
        data: buffer,
        width: side, height: side,
        bitsPerComponent: 8, bytesPerRow: side * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return 1 }

    context.interpolationQuality = .medium
    context.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side))

    var total: CGFloat = 0
    for cell in 0..<count {
        let r = CGFloat(buffer[cell * 4]) / 255
        let g = CGFloat(buffer[cell * 4 + 1]) / 255
        let b = CGFloat(buffer[cell * 4 + 2]) / 255
        total += 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
    return total / CGFloat(count)
}
