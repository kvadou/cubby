import SwiftUI

struct SignInView: View {
    @Environment(SessionStore.self) private var session
    @State private var email = ""
    @State private var password = ""
    @State private var error: String?
    @State private var working = false
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Cubby", systemImage: "house.fill")
                            .font(.title2.bold())
                            .foregroundStyle(.tint)
                        Text("Check-ins, messages, and tuition from your child's center.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.clear)
                }

                Section {
                    TextField("Email", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                        .accessibilityIdentifier("email")
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit(signIn)
                        .accessibilityIdentifier("password")
                } footer: {
                    if let error {
                        Label(error, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                            .font(.footnote)
                            .accessibilityIdentifier("signInError")
                    }
                }

                Section {
                    Button(action: signIn) {
                        HStack {
                            Spacer()
                            if working { ProgressView() } else { Text("Sign In").font(.headline) }
                            Spacer()
                        }
                    }
                    .disabled(working || email.isEmpty || password.isEmpty)
                    .accessibilityIdentifier("signIn")
                }
            }
            .navigationTitle("Welcome")
            .sensoryFeedback(.error, trigger: error)
        }
    }

    private func signIn() {
        guard !working, !email.isEmpty, !password.isEmpty else { return }
        working = true
        error = nil
        Task {
            defer { working = false }
            do {
                try await session.signIn(email: email, password: password)
            } catch {
                self.error = (error as? APIError)?.localizedDescription ?? "Couldn't sign in. Try again."
            }
        }
    }
}
