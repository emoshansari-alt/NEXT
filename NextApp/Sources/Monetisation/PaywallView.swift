import NextKit
import SwiftUI

/// NEXT+.
///
/// Reached only when someone goes looking for it, never at launch and never as an interruption
/// (`PRODUCT_SPEC.md` §12). In a normal build it is not reachable at all — see
/// `MonetisationAvailability`.
struct PaywallView: View {

    @State var model: PaywallViewModel

    var body: some View {
        Form {
            if model.isPlus {
                Section {
                    Text("NEXT+ is on for this Apple ID.")
                        .accessibilityIdentifier("paywall-active")
                }
            }

            explanationSection

            if let notice = model.notice {
                Section {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("paywall-notice")
                }
            }

            productsSection
            restoreSection
        }
        .navigationTitle(NextPlusCopy.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
    }

    // MARK: Sections

    @ViewBuilder
    private var explanationSection: some View {
        Section {
            if model.benefits.isEmpty {
                // The honest state, and the one that ships. Nothing is behind the paywall, so
                // there is nothing to advertise and the screen says exactly that.
                Text(NextPlusCopy.nothingIsGatedYet)
                    .accessibilityIdentifier("paywall-nothing-gated")
            } else {
                ForEach(model.benefits, id: \.self) { benefit in
                    Label(benefit, systemImage: "checkmark")
                }
            }
        }
    }

    @ViewBuilder
    private var productsSection: some View {
        if model.products.isEmpty {
            Section {
                Text("Nothing is available to buy right now.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("paywall-no-products")
            }
        } else {
            Section {
                ForEach(model.products, id: \.id) { product in
                    Button {
                        Task { await model.buy(product.id) }
                    } label: {
                        row(for: product)
                    }
                    .disabled(model.isWorking)
                    .accessibilityIdentifier("paywall-buy-\(product.kind.rawValue)")
                }
            } header: {
                Text("Options")
            }
        }
    }

    private var restoreSection: some View {
        Section {
            Button(NextPlusCopy.restore) {
                Task { await model.restore() }
            }
            .disabled(model.isWorking)
            .accessibilityIdentifier("paywall-restore")
        } footer: {
            Text("If you have bought NEXT+ before on this Apple ID, this brings it back.")
        }
    }

    private func row(for product: PurchasableProduct) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(product.displayName)
                    if product.isPrimary {
                        Text(NextPlusCopy.primaryBadge)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.tint.opacity(0.15), in: Capsule())
                    }
                }
                Text(NextPlusCopy.period(for: product.kind))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // The store's own string. NEXT never formats a price.
            Text(product.displayPrice)
                .monospacedDigit()
        }
    }
}
