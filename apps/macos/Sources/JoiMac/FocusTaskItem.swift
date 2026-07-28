import Foundation

struct FocusTaskItem: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.completedAt = isCompleted ? completedAt : nil
    }
}
