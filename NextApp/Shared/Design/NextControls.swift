import SwiftUI

/// Buttons.
///
/// Two styles and no others. The primary is a solid ballpoint block — Index Card's own accent
/// doing the one job an accent should. The secondary is **outlined or underlined**, borrowed from
/// the Margin direction (D-023): an outline keeps the card's paper quality where a second filled
/// button would turn the screen into a control panel.
///
/// Both guarantee a 44-point target regardless of their label, which is what the accessibility
/// audit enforces.

/// The one action the screen is asking for. At most one per screen.
struct PrimaryBlockStyle: ButtonStyle {

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NextType.control)
            .foregroundStyle(isEnabled ? NextPalette.onBiro : NextPalette.inkSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: NextMetrics.controlHeight(typeSize))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: NextMetrics.controlRadius, style: .continuous)
                    .fill(isEnabled ? NextPalette.biro : NextPalette.edge)
            )
            // Presses in rather than fading. On a direction built from a physical object, a
            // control that recedes under the finger is the only touch feedback that makes sense.
            //
            // Under Reduce Motion the movement is removed rather than slowed — the still
            // equivalent is the opacity change, which carries the same information without
            // anything travelling. Animating a scale more gently is still a scale.
            .pressFeedback(configuration.isPressed, reduceMotion: reduceMotion)
    }
}

/// Everything that is not the one action: an outlined block.
struct OutlinedBlockStyle: ButtonStyle {

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NextType.control)
            .foregroundStyle(isEnabled ? NextPalette.ink : NextPalette.inkSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: NextMetrics.controlHeight(typeSize))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: NextMetrics.controlRadius, style: .continuous)
                    .strokeBorder(NextPalette.ink.opacity(0.35), lineWidth: 1.5)
            )
            .pressFeedback(configuration.isPressed, reduceMotion: reduceMotion)
    }
}

private extension View {

    /// The one press treatment both block styles use, with its Reduce Motion equivalent.
    ///
    /// Written once rather than twice because the two styles differing here is exactly the kind
    /// of drift nobody notices: a button that presses in and a button that does not, on the same
    /// screen, reads as a bug in one of them.
    @ViewBuilder
    func pressFeedback(_ isPressed: Bool, reduceMotion: Bool) -> some View {
        if reduceMotion {
            opacity(isPressed ? 0.7 : 1)
        } else {
            scaleEffect(isPressed ? 0.985 : 1)
                .animation(NextMotion.press, value: isPressed)
        }
    }
}

/// A quiet text action — "I'm stuck", "Not this", "Everything".
///
/// Underlined, which is the annotation vernacular the Margin direction contributed and also the
/// most unambiguously tappable treatment plain text has.
struct QuietTextStyle: ButtonStyle {

    var underlined: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NextType.controlSecondary)
            .foregroundStyle(NextPalette.inkSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .overlay(alignment: .bottom) {
                if underlined {
                    // Full strength, matching the label. A faded rule reads as decoration and
                    // fails the contrast the text beside it passes.
                    Rectangle()
                        .fill(NextPalette.inkSecondary)
                        .frame(height: 1)
                        .offset(y: 2)
                }
            }
            .padding(.horizontal, 8)
            .frame(minWidth: NextMetrics.tapTarget, minHeight: NextMetrics.tapTarget)
            .contentShape(.rect)
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}

extension ButtonStyle where Self == PrimaryBlockStyle {
    static var primaryBlock: PrimaryBlockStyle { PrimaryBlockStyle() }
}

extension ButtonStyle where Self == OutlinedBlockStyle {
    static var outlinedBlock: OutlinedBlockStyle { OutlinedBlockStyle() }
}

extension ButtonStyle where Self == QuietTextStyle {
    static var quietText: QuietTextStyle { QuietTextStyle() }
    static var quietTextPlain: QuietTextStyle { QuietTextStyle(underlined: false) }
}

/// A compact outlined choice — the Focus timer presets, and anything else offered as a short row
/// of alternatives. Sized to the fingertip minimum in both directions.
struct ChipStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NextType.controlSecondary)
            .foregroundStyle(NextPalette.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: NextMetrics.tapTarget, minHeight: NextMetrics.tapTarget)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(NextPalette.ink.opacity(0.28), lineWidth: 1.5)
            )
            .contentShape(.rect)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension ButtonStyle where Self == ChipStyle {
    static var chip: ChipStyle { ChipStyle() }
}
