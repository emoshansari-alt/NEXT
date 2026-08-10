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

/// What an element is **actually drawn in**: its two commonest colours and the ratio between them.
///
/// `performAccessibilityAudit` reports `Contrast failed` and nothing else — no measured ratio and
/// no colours — so a failure on a pair whose palette values clear 6.7:1 cannot be told apart from
/// a failure caused by the wrong appearance being rendered. The audit already reports each issue's
/// element and frame for exactly this reason; this goes one level further and reads the pixels
/// inside that frame.
///
/// Quantised to five bits per channel before counting, so the anti-aliased fringe around a glyph
/// collects into the two colours a reader sees rather than fragmenting into hundreds.
@MainActor
func drawnContrast(in frame: CGRect, of image: UIImage) -> String {
    guard let source = image.cgImage else { return "no image" }

    let scale = image.scale
    let pixels = CGRect(
        x: frame.minX * scale, y: frame.minY * scale,
        width: frame.width * scale, height: frame.height * scale
    ).integral

    guard pixels.width >= 1, pixels.height >= 1,
          let crop = source.cropping(to: pixels)
    else { return "frame outside the screenshot" }

    let width = crop.width
    let height = crop.height
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: width * height * 4)
    buffer.initialize(repeating: 0, count: width * height * 4)
    defer { buffer.deallocate() }

    guard let context = CGContext(
        data: buffer,
        width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return "could not read the pixels" }

    context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))

    var counts: [UInt32: Int] = [:]
    for pixel in 0..<(width * height) {
        let r = UInt32(buffer[pixel * 4] & 0xF8)
        let g = UInt32(buffer[pixel * 4 + 1] & 0xF8)
        let b = UInt32(buffer[pixel * 4 + 2] & 0xF8)
        counts[r << 16 | g << 8 | b, default: 0] += 1
    }

    let ranked = counts.sorted { $0.value > $1.value }
    guard let background = ranked.first else { return "no pixels" }
    // The commonest colour is the ground; the ink is the commonest colour that is not simply a
    // near-neighbour of it, so an anti-aliasing band does not get reported as the text colour.
    guard let foreground = ranked.dropFirst().first(where: { distance($0.key, background.key) > 96 })
    else { return "one colour only: \(hex(background.key))" }

    let ratio = contrast(foreground.key, background.key)
    return String(
        format: "%@ on %@ = %.2f:1", hex(foreground.key), hex(background.key), ratio
    )
}

private func hex(_ packed: UInt32) -> String {
    let value = String(packed, radix: 16, uppercase: true)
    return String(repeating: "0", count: max(0, 6 - value.count)) + value
}

/// Written out rather than mapped over a literal array of shifts: the closure version made the
/// type checker give up outright — "unable to type-check this expression in reasonable time" —
/// on the mix of `UInt32` shifting, `Int` subtraction and `abs`.
private func channels(_ packed: UInt32) -> (r: Int, g: Int, b: Int) {
    let r = Int((packed >> 16) & 0xFF)
    let g = Int((packed >> 8) & 0xFF)
    let b = Int(packed & 0xFF)
    return (r, g, b)
}

private func distance(_ a: UInt32, _ b: UInt32) -> Int {
    let first = channels(a)
    let second = channels(b)
    return abs(first.r - second.r) + abs(first.g - second.g) + abs(first.b - second.b)
}

private func luminance(_ packed: UInt32) -> CGFloat {
    let raw = channels(packed)

    func component(_ value: Int) -> CGFloat {
        let scaled = CGFloat(value) / 255
        if scaled <= 0.03928 { return scaled / 12.92 }
        return pow((scaled + 0.055) / 1.055, 2.4)
    }

    return 0.2126 * component(raw.r) + 0.7152 * component(raw.g) + 0.0722 * component(raw.b)
}

private func contrast(_ a: UInt32, _ b: UInt32) -> CGFloat {
    let first = luminance(a)
    let second = luminance(b)
    return (max(first, second) + 0.05) / (min(first, second) + 0.05)
}
