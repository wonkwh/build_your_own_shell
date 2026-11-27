import EventKit

/// 미리 알림 가져오기·내보내기. EventKit 객체는 콜백 안에서 값으로 바꿔 넘긴다.
enum Reminders {
    struct Item: Sendable {
        var id: String
        var title: String
        var notes: String
        var due: Date?
        var list: String
    }

    nonisolated(unsafe) static let store = EKEventStore()

    static func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToReminders()) ?? false
    }

    static func incomplete() async -> [Item] {
        await withCheckedContinuation { cont in
            let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
            store.fetchReminders(matching: predicate) { reminders in
                let items = (reminders ?? []).map { r in
                    Item(id: r.calendarItemIdentifier, title: r.title ?? "", notes: r.notes ?? "",
                         due: r.dueDateComponents.flatMap { Calendar.current.date(from: $0) }, list: r.calendar?.title ?? "")
                }
                cont.resume(returning: items)
            }
        }
    }

    static var lists: [(id: String, title: String)] {
        store.calendars(for: .reminder).map { ($0.calendarIdentifier, $0.title) }
    }

    /// 미리 알림을 TaskPaper 줄로 바꾼다. 메모는 한 단계 들여쓴 메모 줄이 된다.
    static func lines(for item: Item, indent: String) -> [String] {
        var head = indent + "- " + item.title
        if let due = item.due { head += " @due(\(DateParser.format(due)))" }
        let notes = item.notes.split(separator: "\n", omittingEmptySubsequences: true).map { indent + "\t" + $0 }
        return [head] + notes
    }

    static func remove(ids: [String]) {
        for id in ids {
            if let r = store.calendarItem(withIdentifier: id) as? EKReminder { try? store.remove(r, commit: false) }
        }
        try? store.commit()
    }

    /// 항목들을 미리 알림으로 만든다.
    static func export(_ items: [(title: String, notes: String, due: Date?)], toList listID: String?) throws {
        let calendar = listID.flatMap { store.calendar(withIdentifier: $0) } ?? store.defaultCalendarForNewReminders()
        for item in items {
            let r = EKReminder(eventStore: store)
            r.title = item.title
            r.notes = item.notes.isEmpty ? nil : item.notes
            r.calendar = calendar
            if let due = item.due {
                r.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            }
            try store.save(r, commit: false)
        }
        try store.commit()
    }
}
