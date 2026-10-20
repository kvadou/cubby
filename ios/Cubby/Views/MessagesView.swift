import SwiftUI

/// What the center sent: approved by a director in the web app, delivered here.
struct MessagesView: View {
    @Environment(SessionStore.self) private var session
    @Binding var unread: Int
    @State private var messages = Loader<[FamilyMessage]>()

    var body: some View {
        NavigationStack {
            LoadingView(loader: messages, retry: load) { list in
                List {
                    ForEach(list) { message in
                        NavigationLink(value: message) { MessageRow(message: message) }
                    }
                }
                .listStyle(.plain)
                .overlay {
                    if list.isEmpty {
                        ContentUnavailableView("No messages yet", systemImage: "tray",
                                               description: Text("Messages from your center will appear here."))
                    }
                }
                .refreshable { await load() }
                .navigationDestination(for: FamilyMessage.self) { message in
                    MessageDetail(message: message) { read in markRead(read, in: list) }
                }
            }
            .navigationTitle("Messages")
        }
        .task { await load() }
    }

    private func load() async {
        await messages.load(session) { try await $0.messages() }
        if case .loaded(let list) = messages.phase { unread = list.filter(\.isUnread).count }
    }

    private func markRead(_ message: FamilyMessage, in list: [FamilyMessage]) {
        guard message.isUnread else { return }
        Task {
            guard let updated = try? await session.client.markRead(message.id) else { return }
            let next = list.map { $0.id == updated.id ? updated : $0 }
            messages.replace(next)
            unread = next.filter(\.isUnread).count
        }
    }
}

private struct MessageRow: View {
    let message: FamilyMessage
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(message.isUnread ? Color.accentColor : .clear)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                // At accessibility sizes the time moves under the subject so the subject isn't cut off.
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
                layout {
                    Text(message.subject)
                        .font(message.isUnread ? .headline : .body)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                    Text(message.sentAt, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(message.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityHint(message.isUnread ? "Unread" : "")
    }
}

private struct MessageDetail: View {
    let message: FamilyMessage
    let onAppear: (FamilyMessage) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(message.subject).font(.title2.bold())
                    Text("From \(message.from) · \(message.sentAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(message.body)
                    .font(.body)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { onAppear(message) }
    }
}
