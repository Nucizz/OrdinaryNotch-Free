import Foundation

struct AgendaItem: Identifiable, Equatable {
    let id: String
    let title: String
    let date: Date?
    let isReminder: Bool
    let allDay: Bool
}
