import EventKit
import SwiftUI

struct DayCalendarEvent: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let location: String?
    let calendarTitle: String?
    let calendarColor: Color?
}

@MainActor
final class CalendarEventStore: ObservableObject {
    enum AccessState: Equatable {
        case checking
        case needsPermission
        case denied
        case loading
        case ready
        case failed
    }

    @Published private(set) var accessState: AccessState = .checking
    @Published private(set) var events: [DayCalendarEvent] = []

    private let eventStore = EKEventStore()

    func checkAccessAndLoad() async {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized:
            await loadEvents()
        case .notDetermined:
            accessState = .needsPermission
        case .denied, .restricted, .writeOnly:
            accessState = .denied
        @unknown default:
            accessState = .failed
        }
    }

    func requestAccessAndLoad() async {
        accessState = .loading

        do {
            let granted = try await eventStore.requestFullAccessToEvents()

            if granted {
                await loadEvents()
            } else {
                accessState = .denied
            }
        } catch {
            accessState = .failed
        }
    }

    func loadEvents() async {
        accessState = .loading

        let calendars = eventStore.calendars(for: .event)
        let range = Calendar.current.localDayRange(for: Date())
        let predicate = eventStore.predicateForEvents(
            withStart: range.start,
            end: range.end,
            calendars: calendars.isEmpty ? nil : calendars
        )

        let loadedEvents = eventStore.events(matching: predicate)
            .map(DayCalendarEvent.init(event:))
            .sorted()

        events = loadedEvents
        accessState = .ready
    }
}

private extension DayCalendarEvent {
    init(event: EKEvent) {
        id = event.eventIdentifier ?? UUID().uuidString
        title = event.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Untitled event"
        startDate = event.startDate
        endDate = event.endDate
        isAllDay = event.isAllDay
        location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        calendarTitle = event.calendar.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        calendarColor = event.calendar.cgColor.map { Color(cgColor: $0) }
    }
}

private extension Array where Element == DayCalendarEvent {
    func sorted() -> [DayCalendarEvent] {
        sorted { first, second in
            if first.isAllDay != second.isAllDay {
                return first.isAllDay
            }

            if first.startDate != second.startDate {
                return first.startDate < second.startDate
            }

            return first.title.localizedCaseInsensitiveCompare(second.title) == .orderedAscending
        }
    }
}

private extension Calendar {
    func localDayRange(for date: Date) -> (start: Date, end: Date) {
        let start = startOfDay(for: date)
        let end = self.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return (start, end)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
