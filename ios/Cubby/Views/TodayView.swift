import SwiftUI

/// Each child's day: whether they're checked in now, then the last two weeks.
struct TodayView: View {
    @Environment(SessionStore.self) private var session
    @Binding var unread: Int
    @State private var home = Loader<FamilyHome>()
    @State private var history: [Int: [AttendanceDay]] = [:]

    var body: some View {
        NavigationStack {
            LoadingView(loader: home, retry: load) { home in
                let clock = CenterClock(identifier: home.center.timezone)
                List {
                    if home.children.isEmpty {
                        ContentUnavailableView("No children yet", systemImage: "figure.and.child.holdinghands",
                                               description: Text("\(home.center.name) hasn't added your children."))
                    }
                    ForEach(home.children) { child in
                        Section {
                            ChildTodayRow(child: child, clock: clock)
                            ForEach(history[child.id] ?? []) { day in
                                AttendanceRow(day: day, clock: clock, isToday: day.on == home.today)
                            }
                        } header: {
                            Text(child.firstName)
                        } footer: {
                            if (history[child.id] ?? []).isEmpty {
                                Text("No check-ins in the last two weeks.")
                            }
                        }
                    }
                    Section {
                        LabeledContent("Center", value: home.center.name)
                        LabeledContent("Director", value: home.center.directorName)
                    }
                    Section {
                        Button("Sign Out", role: .destructive) { Task { await session.signOut() } }
                            .accessibilityIdentifier("signOut")
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await load() }
                .navigationTitle("Hi, \(home.family.guardianName.split(separator: " ").first.map(String.init) ?? "there")")
            }
            .navigationTitle("Today")
        }
        .task { await load() }
    }

    private func load() async {
        await home.load(session) { try await $0.home() }
        guard case .loaded(let value) = home.phase else { return }
        unread = value.unreadMessages
        for child in value.children {
            history[child.id] = (try? await session.client.attendance(childID: child.id)) ?? []
        }
    }
}

private struct ChildTodayRow: View {
    let child: FamilyHome.Child
    let clock: CenterClock

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var headline: String {
        switch (child.today?.checkedInAt, child.today?.checkedOutAt) {
        case (.some, .none): "Checked in"
        case (.some, .some): "Picked up"
        default: child.status == "waitlisted" ? "On the waitlist" : "Not checked in today"
        }
    }

    private var detail: String {
        if let day = child.today {
            let arrived = "Arrived \(clock.time(day.checkedInAt))"
            guard let out = day.checkedOutAt else { return "\(arrived) · \(child.classroom ?? "")" }
            return "\(arrived) · Left \(clock.time(out))"
        }
        return child.classroom.map { "\($0) classroom" } ?? "No classroom yet"
    }

    private var icon: String {
        switch (child.today?.checkedInAt, child.today?.checkedOutAt) {
        case (.some, .none): "checkmark.circle.fill"
        case (.some, .some): "house.circle.fill"
        default: "moon.circle.fill"
        }
    }

    private var tint: Color {
        child.today != nil && child.today?.checkedOutAt == nil ? .green : .secondary
    }
}

private struct AttendanceRow: View {
    let day: AttendanceDay
    let clock: CenterClock
    let isToday: Bool

    var body: some View {
        LabeledContent {
            Text(range).monospacedDigit()
        } label: {
            Text(isToday ? "Today" : day.on.shortLabel)
        }
        .font(.subheadline)
    }

    private var range: String {
        let start = clock.time(day.checkedInAt)
        return day.checkedOutAt.map { "\(start) – \(clock.time($0))" } ?? "\(start) – now"
    }
}
