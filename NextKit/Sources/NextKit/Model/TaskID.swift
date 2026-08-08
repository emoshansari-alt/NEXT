/// A task's stable identity.
///
/// Deliberately a wrapper over `String` rather than `UUID`. `NextKit` is forbidden from
/// calling `UUID()` (DECISIONS.md D-007) because a hidden source of randomness makes the
/// engine untestable; identifiers are minted by an `IDProvider` at the app boundary and
/// merely carried here. Tests can therefore use readable ids such as `TaskID("chem")`.
public struct TaskID: Hashable, Sendable, Codable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

extension TaskID: CustomStringConvertible {
    public var description: String { rawValue }
}
