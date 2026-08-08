/// The single thing NEXT is telling the user to do.
public struct Recommendation: Hashable, Sendable {

    /// The task the action belongs to.
    public let task: TaskItem

    public init(task: TaskItem) {
        self.task = task
    }
}
