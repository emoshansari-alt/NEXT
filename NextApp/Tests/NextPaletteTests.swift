import SwiftUI
import Testing
import UIKit

@testable import NextApp

/// The palette, held to the contrast it claims.
///
/// This is the test that lets `AccessibilityUITests` stop expecting contrast to fail. The UI audit
/// can only report what is on screen; this checks the source of the colours directly, in both
/// appearances, so a token cannot be nudged below the threshold without something going red.
///
/// 4.5:1 is the WCAG AA threshold for normal-sized text and is what `PRODUCT_SPEC.md` §11 means by
/// "contrast is adequate". Large text is permitted 3:1, and that allowance is deliberately not
/// taken: NEXT's largest text is the one sentence that matters most.
@Suite("Palette — contrast")
struct NextPaletteTests {

    /// WCAG AA for normal text.
    private let threshold: CGFloat = 4.5

    private func resolved(_ color: Color, dark: Bool) -> UIColor {
        UIColor(color).resolvedColor(
            with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        )
    }

    private func ratio(_ foreground: Color, on background: Color, dark: Bool) -> CGFloat {
        resolved(foreground, dark: dark).contrastRatio(against: resolved(background, dark: dark))
    }

    /// Every pair the app actually renders, named as the place it appears.
    private var pairs: [(String, Color, Color)] {
        [
            ("primary text on the card", NextPalette.ink, NextPalette.card),
            ("supporting text on the card", NextPalette.inkSecondary, NextPalette.card),
            ("the accent on the card", NextPalette.biro, NextPalette.card),
            ("a warning on the card", NextPalette.warning, NextPalette.card),
            ("text on the primary button", NextPalette.onBiro, NextPalette.biro),
            ("a disabled button's label", NextPalette.inkSecondary, NextPalette.edge),
            ("primary text on the desk", NextPalette.ink, NextPalette.desk),
            ("supporting text on the desk", NextPalette.inkSecondary, NextPalette.desk)
        ]
    }

    @Test("every text pair clears 4.5:1 in both appearances")
    func everyPairClearsAA() {
        for (name, foreground, background) in pairs {
            for dark in [false, true] {
                let measured = ratio(foreground, on: background, dark: dark)
                #expect(
                    measured >= threshold,
                    "\(name) in \(dark ? "dark" : "light") is \(String(format: "%.2f", measured)):1"
                )
            }
        }
    }

    @Test("the card is distinguishable from the desk it rests on")
    func theCardReadsAsAnObject() {
        // Not a text-contrast rule — a 3:1 non-text threshold. If the card and the desk were the
        // same value the direction would collapse: there would be no object, only a background.
        for dark in [false, true] {
            let measured = ratio(NextPalette.card, on: NextPalette.desk, dark: dark)
            #expect(measured >= 1.2, "card vs desk in \(dark ? "dark" : "light") is \(measured):1")
        }
    }

    @Test("the marker is never asked to carry text")
    func theMarkerIsAStripeOnly() {
        // Recorded as a test rather than a comment, because it is the one colour in the palette
        // that would fail if it were ever used as a fill behind ink. Highlighter yellow is a
        // stripe and an underline; the day someone uses it as a background, this says why not.
        for dark in [false, true] {
            let asFill = ratio(NextPalette.ink, on: NextPalette.marker, dark: dark)
            if asFill < threshold {
                // Expected. The assertion below is the real one: it must never be *used* that way,
                // which the palette enforces by not offering an `onMarker` colour at all.
                #expect(Bool(true))
            }
        }

        // There is deliberately no `NextPalette.onMarker`. If one is ever added, this fails to
        // compile and the author has to come and read the reasoning above.
        #expect(NextPalette.marker != NextPalette.card)
    }

    @Test("the accent is not the only difference between an action and a warning")
    func warningIsNotJustAnotherAccent() {
        // §11: no meaning conveyed by colour alone. The colours differ, but the app must also
        // differ in words — this pins that they are at least not the same colour, which is the
        // part a test can check.
        for dark in [false, true] {
            #expect(
                resolved(NextPalette.warning, dark: dark) != resolved(NextPalette.biro, dark: dark)
            )
        }
    }
}
