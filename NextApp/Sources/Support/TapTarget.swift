import SwiftUI

extension View {

    /// Guarantees a control is at least as large as a fingertip, whatever its text.
    ///
    /// NEXT's secondary actions are plain text buttons — "I'm stuck", "Not this", "Stop", "Skip".
    /// They read correctly as quiet, secondary choices, and that is deliberate. But a `Text` in a
    /// button is only as tall as its line: the accessibility audit measured "Everything" at
    /// 73 × 18 points, against the 44 × 44 minimum current platform guidance asks for
    /// (`PRODUCT_SPEC.md` §11).
    ///
    /// A control that small is hard to hit for anyone with a tremor, on a bus, or one-handed —
    /// and "I'm stuck" is used precisely when someone is already having a bad time. The fix is
    /// invisible: the *hit area* grows, the text does not.
    ///
    /// `contentShape` is the half that actually matters. Without it the tappable region is the
    /// glyphs rather than the padded frame, so enlarging the frame alone would look right and
    /// change nothing.
    func accessibleTapTarget(minimum: CGFloat = 44) -> some View {
        frame(minWidth: minimum, minHeight: minimum)
            .contentShape(.rect)
    }
}
