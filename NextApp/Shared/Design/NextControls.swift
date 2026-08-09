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

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NextType.control)
            .foregroundStyle(NextPalette.onBiro)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: NextMetrics.controlHeight(typeSize))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: NextMetrics.controlRadius, style: .continuous)
                    .fill(NextPalette.biro)
            )
            .opacity(isEnabled ? 1 : 0.4)
            // Presses in rather than fading. On a direction built from a physical object, a
            // control that recedes under the finger is the only touch feedback that makes sense.
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(NextMotion.press, value: configuration.isPressed)
    }
}

/// Everything that is not the one action: an outlined block.
struct OutlinedBlockStyle: ButtonStyle {

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.dynamicTypeSize) private var typeSize

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NextType.control)
            .foregroundStyle(NextPalette.ink)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: NextMetrics.controlHeight(typeSize))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: NextMetrics.controlRadius, style: .continuous)
                    .strokeBorder(NextPalette.ink.opacity(0.35), lineWidth: 1.5)
            )
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(NextMotion.press, value: configuration.isPressed)
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
                    Rectangle()
                        .fill(NextPalette.inkSecondary.opacity(0.45))
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
