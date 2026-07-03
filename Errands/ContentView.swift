import SwiftUI

struct ContentView: View {
    @StateObject private var calendarStore = CalendarEventStore()
    @AppStorage("themePreference") private var themePreference: ThemePreference = .system

    private var colorScheme: ColorScheme? {
        switch themePreference {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Today", systemImage: "calendar")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Today")
                            .font(.largeTitle.bold())
                        Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                content
            }
            .navigationTitle("Errands")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        toggleTheme()
                    } label: {
                        Image(systemName: themePreference == .dark ? "moon.fill" : "sun.max.fill")
                    }
                    .accessibilityLabel("Toggle color scheme")
                }
            }
            .task {
                await calendarStore.checkAccessAndLoad()
            }
            .refreshable {
                if calendarStore.accessState == .ready {
                    await calendarStore.loadEvents()
                }
            }
        }
        .preferredColorScheme(colorScheme)
    }

    @ViewBuilder
    private var content: some View {
        switch calendarStore.accessState {
        case .checking, .loading:
            StateView(title: "Checking calendar", message: "Looking for today's events.")
        case .needsPermission:
            StateView(
                title: "Connect Calendar",
                message: "Allow Errands to read your Apple Calendar so today's events can appear here.",
                actionTitle: "Connect Calendar"
            ) {
                await calendarStore.requestAccessAndLoad()
            }
        case .denied:
            StateView(
                title: "Calendar access denied",
                message: "Errands cannot read today's events without calendar access.",
                actionTitle: "Try Again"
            ) {
                await calendarStore.requestAccessAndLoad()
            }
        case .failed:
            StateView(
                title: "Calendar error",
                message: "Today's events could not be loaded.",
                actionTitle: "Retry"
            ) {
                await calendarStore.checkAccessAndLoad()
            }
        case .ready:
            if calendarStore.events.isEmpty {
                StateView(title: "No events today", message: "Your Apple Calendar is clear for today.")
            } else {
                Section {
                    ForEach(calendarStore.events) { event in
                        EventRow(event: event)
                    }
                }
            }
        }
    }

    private func toggleTheme() {
        switch themePreference {
        case .system, .light:
            themePreference = .dark
        case .dark:
            themePreference = .light
        }
    }
}

private struct StateView: View {
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() async -> Void)?

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .foregroundStyle(.secondary)

                if let actionTitle, let action {
                    Button(actionTitle) {
                        Task {
                            await action()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.vertical, 8)
        }
    }
}

private struct EventRow: View {
    let event: DayCalendarEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(event.calendarColor ?? Color.accentColor)
                .frame(width: 10, height: 10)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 6) {
                Label(eventTime, systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(event.title)
                    .font(.headline)

                if let calendarTitle = event.calendarTitle {
                    Text(calendarTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let location = event.location {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var eventTime: String {
        if event.isAllDay {
            return "All day"
        }

        return "\(event.startDate.formatted(date: .omitted, time: .shortened)) - \(event.endDate.formatted(date: .omitted, time: .shortened))"
    }
}

private enum ThemePreference: String {
    case system
    case light
    case dark
}
