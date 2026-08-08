import Foundation

/// A stage of partial progress on a piece of work, used when the task itself says nothing
/// about how it breaks down.
///
/// Three stages, in the order the work happens: get the shape of the thing down, produce the
/// first real piece, then finish one part properly. That sequence is the spec's worked example
/// — a paper due tonight becomes outline, then introduction, then first section
/// (PRODUCT_SPEC.md §4.12) — generalised to the other kinds of work a student actually has.
///
/// These are a **fallback**, and the planner labels them as one. Real substeps the user
/// recorded always win, because a generic stage is a guess about the shape of someone else's
/// assignment and a recorded substep is not a guess at all.
///
/// Every instruction below names something that can be *produced*, so that finishing a rung
/// leaves the user holding something real. None of them produces work the user did not do:
/// the academic-integrity boundary in PRODUCT_SPEC.md §1 is a property of this copy, and
/// `MinimumWinHonestyTests` sweeps it.
public enum MinimumWinStage: String, Hashable, Sendable, CaseIterable, Codable {

    /// The shape of the whole thing, written down. Cheap, and it makes everything after it
    /// possible.
    case outline

    /// The first real piece of the actual deliverable.
    case opening

    /// One complete part, done properly rather than sketched.
    case firstPart

    /// What to do at this stage for a given kind of work.
    ///
    /// `kind` is `nil` when the title gave nothing away. The instructions for that case are
    /// deliberately about *finding out what the task is*, which is the only thing NEXT can
    /// honestly be sure is useful when it knows nothing about the work.
    public func instruction(for kind: WorkKind?) -> String {
        let ladder = Self.ladder(for: kind)
        switch self {
        case .outline: return ladder.outline
        case .opening: return ladder.opening
        case .firstPart: return ladder.firstPart
        }
    }

    // MARK: - Copy

    /// The three instructions for one kind of work, in stage order.
    struct Ladder {
        let outline: String
        let opening: String
        let firstPart: String
    }

    static func ladder(for kind: WorkKind?) -> Ladder {
        guard let kind else {
            return Ladder(
                outline: "Find the instructions and write down what this has to produce.",
                opening: "Do the first item on that list.",
                firstPart: "Do the next item on that list."
            )
        }

        switch kind {
        case .writing:
            return Ladder(
                outline: "Write a bare outline: your points, in the order you will make them.",
                opening: "Write the introduction.",
                firstPart: "Write the first section in full."
            )

        case .reading:
            return Ladder(
                outline: "Skim the headings and write down what the text covers.",
                opening: "Read the first section.",
                firstPart: "Write three lines on what that section said."
            )

        case .problemSet:
            return Ladder(
                outline: "Read every question and mark the ones you can already do.",
                opening: "Answer the first question you marked.",
                firstPart: "Answer the rest of the ones you marked."
            )

        case .presentation:
            return Ladder(
                outline: "List the three points the talk has to make.",
                opening: "Make a title slide and one slide per point.",
                firstPart: "Fill in the first point's slide properly."
            )

        case .revision:
            return Ladder(
                outline: "List the topics it covers and mark the ones you have not gone over.",
                opening: "Read your notes on the first topic you marked.",
                firstPart: "Cover the page and write down what you remember of it."
            )

        case .practice:
            return Ladder(
                outline: "Set out what you need and pick the one section to work on.",
                opening: "Run that section once, slowly.",
                firstPart: "Repeat that section until it is clean."
            )

        case .correspondence:
            return Ladder(
                outline: "Write down the one thing you need from them.",
                opening: "Open a message and fill in the recipient and the subject.",
                firstPart: "Write the message in your own words and send it."
            )

        case .admin:
            return Ladder(
                outline: "Open the form and read what it asks for.",
                opening: "Fill in every field you already have to hand.",
                firstPart: "Track down the one missing detail and finish the form."
            )
        }
    }
}
