import SwiftUI

@main
struct CubbyApp: App {
    @State private var session = SessionStore()

    init() {
        // UI tests start from a clean slate so sign-in is always exercised.
        if ProcessInfo.processInfo.arguments.contains("-resetSession") { Keychain.delete() }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
        }
    }
}

struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        switch session.state {
        case .signedOut:
            SignInView()
        case .signedIn:
            MainTabs()
        }
    }
}

struct MainTabs: View {
    @Environment(SessionStore.self) private var session
    @State private var unread = 0

    var body: some View {
        TabView {
            TodayView(unread: $unread)
                .tabItem { Label("Today", systemImage: "sun.max") }
            MessagesView(unread: $unread)
                .tabItem { Label("Messages", systemImage: "bubble.left.and.text.bubble.right") }
                .badge(unread)
            BillingView()
                .tabItem { Label("Billing", systemImage: "creditcard") }
        }
    }
}
