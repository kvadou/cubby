import SwiftUI

/// Loads a value from the API and handles the session ending, so each screen only describes its
/// content, empty, and error states.
@MainActor
@Observable
final class Loader<Value: Sendable> {
    enum Phase {
        case loading
        case loaded(Value)
        case failed(APIError)
    }

    private(set) var phase: Phase = .loading

    func load(_ session: SessionStore, _ fetch: @Sendable (APIClient) async throws -> Value) async {
        do {
            phase = .loaded(try await fetch(session.client))
        } catch APIError.unauthorized {
            session.endSession()
        } catch let error as APIError {
            phase = .failed(error)
        } catch {
            phase = .failed(.server(status: 0, message: nil))
        }
    }

    func replace(_ value: Value) { phase = .loaded(value) }
}

/// Spinner, error, or content, the same way on every tab.
struct LoadingView<Value: Sendable, Content: View>: View {
    let loader: Loader<Value>
    let retry: () async -> Void
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        switch loader.phase {
        case .loading:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let error):
            ContentUnavailableView {
                Label(error == .offline ? "The demo is offline" : "Couldn't load this",
                      systemImage: error == .offline ? "moon.zzz" : "wifi.exclamationmark")
            } description: {
                Text(error.localizedDescription)
            } actions: {
                Button("Try Again") { Task { await retry() } }
                    .buttonStyle(.borderedProminent)
            }
        case .loaded(let value):
            content(value)
        }
    }
}

/// Shows times in the center's time zone, which is what a parent standing at the door sees.
struct CenterClock {
    let timeZone: TimeZone

    init(identifier: String) {
        timeZone = TimeZone(identifier: identifier) ?? .current
    }

    func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone))
    }

    func dayAndTime(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, timeZone: timeZone))
    }
}

extension CalendarDay {
    /// "Mon, Oct 19"; noon UTC keeps the day the same in every zone.
    var shortLabel: String {
        date.formatted(Date.FormatStyle(timeZone: TimeZone(identifier: "UTC")!).weekday(.abbreviated).month(.abbreviated).day())
    }

    var mediumLabel: String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: TimeZone(identifier: "UTC")!))
    }
}

extension Decimal {
    var dollars: String { formatted(.currency(code: "USD")) }
}
