import SwiftUI
import UIKit

struct AccountSettingsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(AppSession.self) private var session
    @State private var name = ""
    @State private var saving = false
    @State private var signingOut = false
    @State private var confirmSignOut = false
    @State private var message: String?
    @State private var saveFailed = false
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Display name", text: $name)
                        .textContentType(.nickname).textInputAutocapitalization(.words)
                        .autocorrectionDisabled().disabled(saving)
                    Button(saving ? "Saving…" : "Save name") { Task { await saveName() } }
                        .disabled(saving || trimmedName.isEmpty || trimmedName.unicodeScalars.count > 80 || trimmedName == session.displayName)
                    if let message {
                        Text(message).font(.footnote).foregroundStyle(saveFailed ? Color.red : Color.secondary)
                    }
                } header: { Text("Your profile") }
                footer: { Text("Your crew can see your name. Use up to 80 characters.") }

                Section {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } label: { Label("Location settings", systemImage: "location") }
                } header: { Text("Location") }
                footer: { Text("Location records your route and distance during a run. Your route is private; your crew sees run summaries.") }

                Section("Running") {
                    NavigationLink("Run guidance", destination: RunCueSettingsView())
                }

                Section("About") {
                    LabeledContent("French Fried", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    Button("Show onboarding") { session.replayOnboarding() }
                }
                Section("Account") {
                    Button(signingOut ? "Signing out…" : "Sign out", role: .destructive) { confirmSignOut = true }
                        .disabled(signingOut || saving)
                    if let error = session.error { Text(error).font(.footnote).foregroundStyle(.red) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.98, green: 0.96, blue: 0.92))
            .navigationTitle("Settings")
            .task { name = session.displayName }
            .confirmationDialog("Sign out of French Fried?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    Task { signingOut = true; await session.signOut(); signingOut = false }
                }
            } message: { Text("Your saved runs and crew will be here when you sign back in.") }
        }
    }

    private func saveName() async {
        saving = true; message = nil
        defer { saving = false }
        do {
            try await session.updateProfile(name: trimmedName)
            name = session.displayName; saveFailed = false; message = "Name saved."
        } catch { saveFailed = true; message = "Couldn’t save your name. Check your connection and try again." }
    }
}
