/// Everything that can go wrong on the way to a validated answer.
///
/// Vendor-neutral by construction. There is no case naming a company, a model, an HTTP status
/// or a rate-limit header, because the Phase 8 provider decision is deliberately still open
/// (DECISIONS.md D-005) and a leaked vendor concept here would quietly close it. A provider that
/// needs to distinguish its own failures does so through `providerFailure(operation:code:)`,
/// whose code is opaque to everything above it.
///
/// ## No case carries user text
///
/// Same rule as `ValidationFailure`, for the same reason: errors get logged, and PRIVACY.md says
/// task text never appears in a log line, breadcrumb or crash report. `malformedResponse` in
/// particular does *not* carry the bytes that failed to parse, tempting though that is —
/// a malformed response frequently contains a mangled copy of the prompt.
public enum IntelligenceError: Error, Hashable, Sendable {

    /// The provider did not answer in time.
    case timedOut(IntelligenceOperation)

    /// The caller went away before the answer arrived.
    case cancelled(IntelligenceOperation)

    /// This provider does not do this operation at all.
    ///
    /// Not a fault. `TemplateFallbackProvider` genuinely cannot estimate a duration without
    /// guessing, and says so rather than inventing a number.
    case unsupported(IntelligenceOperation)

    /// The provider could be asked, but not right now.
    case unavailable(UnavailabilityCause)

    /// The bytes that came back were not the shape they claimed to be.
    case malformedResponse(IntelligenceOperation)

    /// The response parsed and then failed the gate. The task database is untouched.
    case validationFailed(ValidationFailure)

    /// Something specific to one provider went wrong. The code is that provider's own
    /// vocabulary and means nothing above this layer; it exists so a bug report can be
    /// actioned without the error type learning a vendor's taxonomy.
    case providerFailure(operation: IntelligenceOperation, code: String)
}

/// Why a provider that exists cannot be reached at this moment.
///
/// These are the four situations PRODUCT_SPEC.md §6 requires NEXT to survive without losing
/// core functionality. Each one lands on the same answer: fall back to the deterministic layer.
public enum UnavailabilityCause: String, Hashable, Sendable, CaseIterable, Codable {

    /// No network. The single most common case, and the reason `TemplateFallbackProvider` exists.
    case offline

    /// The user has not agreed to send task text off the device, or has withdrawn agreement.
    /// Declining must leave a fully functional app (PRIVACY.md).
    case consentNotGiven

    /// The hardware cannot run the on-device model. A real constraint for this audience, not a
    /// hypothetical one — see DECISIONS.md D-004.
    case deviceNotCapable

    /// The allowance for this user or this period is used up.
    case quotaExhausted
}
