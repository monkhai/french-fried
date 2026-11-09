import SwiftUI
import AuthenticationServices
import AppleSignIn
import Supabase
import RunTracking
import ProgramCore

@MainActor @Observable
final class AppSession {
    let client = SupabaseClient(
        supabaseURL: BackendConfiguration.url,
        supabaseKey: BackendConfiguration.publishableKey
    )
    let apple = AppleSignInFlow()
    var signedIn = false
    var loading = true
    var error: String?
    var needsOnboarding = false
    var profileLoadFailed = false
    var suggestedName = ""
    var displayName = ""
    var signingIn = false
    var profileLoading = false
    var accountDeleted = false
    private var userID: UUID?
    var recoveryOwnerID: UUID? { userID }
    private var pendingOnboardingKey: String? { userID.map { "onboarding.pending.\($0.uuidString)" } }
    private var requestFailed = false

    func restore() async {
        defer { loading = false }
        do {
            _ = try await client.auth.session
            signedIn = true
            await loadProfile()
        }
        catch { signedIn = false }
    }

    func loadProfile() async {
        guard !profileLoading else { return }
        profileLoading = true
        defer { profileLoading = false }
        do {
            let userID = try await client.auth.session.user.id
            self.userID = userID
            let profiles: [ProfileIdentity] = try await client.from("profiles")
                .select("id, display_name").eq("id", value: userID).execute().value
            displayName = profiles.first?.display_name ?? ""
            needsOnboarding = profiles.isEmpty || (pendingOnboardingKey.map { UserDefaults.standard.bool(forKey: $0) } ?? false)
            profileLoadFailed = false
        } catch {
            profileLoadFailed = true
        }
    }

    func createProfile(name: String) async throws {
        let userID = try await client.auth.session.user.id
        let name = try validatedName(name)
        self.userID = userID
        if let key = pendingOnboardingKey { UserDefaults.standard.set(true, forKey: key) }
        let profile: ProfileIdentity = try await client.from("profiles")
            .upsert(NewProfile(id: userID, display_name: name))
            .select("id, display_name").single().execute().value
        displayName = profile.display_name
    }

    func updateProfile(name: String) async throws {
        let name = try validatedName(name)
        let userID = try await client.auth.session.user.id
        let profile: ProfileIdentity = try await client.from("profiles")
            .update(["display_name": name]).eq("id", value: userID)
            .select("id, display_name").single().execute().value
        displayName = profile.display_name
    }

    func finishOnboarding() {
        if let key = pendingOnboardingKey { UserDefaults.standard.removeObject(forKey: key) }
        needsOnboarding = false
    }

    func replayOnboarding() {
        suggestedName = displayName
        needsOnboarding = true
    }

    private func validatedName(_ name: String) throws -> String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.unicodeScalars.count <= 80 else { throw ProfileError.invalidName }
        return value
    }

    func configure(_ request: ASAuthorizationAppleIDRequest) {
        error = nil
        do { try apple.configure(request); requestFailed = false }
        catch { requestFailed = true; self.error = "Couldn't start Apple sign-in. Please try again." }
    }

    func complete(_ result: Result<ASAuthorization, Error>) async {
        guard !requestFailed, !signingIn else { return }
        signingIn = true
        defer { signingIn = false }
        do {
            let identity = try apple.complete(result)
            _ = try await client.auth.signInWithIdToken(credentials: OpenIDConnectCredentials(
                provider: .apple, idToken: identity.identityToken, nonce: identity.rawNonce))
            if let name = identity.fullName {
                suggestedName = PersonNameComponentsFormatter.localizedString(from: name, style: .default, options: [])
            }
            signedIn = true
            error = nil
            loading = true
            await loadProfile()
            loading = false
        } catch AppleSignInError.cancelled {
            return
        } catch {
            self.error = "Sign-in couldn't be completed. Check your connection and try again."
        }
    }

    func signOut() async {
        do { try await client.auth.signOut(); signedIn = false; error = nil; needsOnboarding = false; profileLoadFailed = false; suggestedName = ""; displayName = ""; userID = nil }
        catch { self.error = "Couldn't sign out. Please try again." }
    }

    func deleteAccount() async throws {
        let owner = try await client.auth.session.user.id
        let result: AccountDeletionResult = try await client.functions.invoke("delete-account",
            options: .init(body: ["confirmation": "DELETE"]))
        guard result.deleted else { throw AccountDeletionError.failed }
        RunRecoveryStore.clearAll(owner: owner)
        UserDefaults.standard.removeObject(forKey: "onboarding.pending.\(owner.uuidString)")
        // Supabase removes its persisted local session before making the sign-out
        // request; the server has already revoked all sessions and deleted the user.
        try? await client.auth.signOut(scope: .local)
        signedIn = false; error = nil; needsOnboarding = false
        profileLoadFailed = false; suggestedName = ""; displayName = ""; userID = nil
        accountDeleted = true
    }

    func save(_ run: RecordedRun, id: UUID, trainingSession: TrainingSession? = nil, sessionCompleted: Bool = false) async throws {
        let prescribedSession = trainingSession.flatMap { selected in
            CouchTo5KPlan.program.sessions.first { $0 == selected }
        }
        let completed = prescribedSession.map { sessionCompleted && run.activeSeconds >= Double($0.totalDurationSeconds) } ?? false
        let params = SaveRunParameters(p_run_id: id, p_started_at: run.startedAt, p_ended_at: run.endedAt,
            p_active_seconds: Int(run.activeSeconds.rounded()), p_distance_meters: run.distanceMeters,
            p_program_id: prescribedSession == nil ? "free-run" : CouchTo5KPlan.program.id,
            p_program_version: prescribedSession == nil ? 1 : CouchTo5KPlan.program.version,
            p_session_id: prescribedSession?.id ?? "free-run",
            p_session_completed: completed, p_points: run.locations)
        try await client.rpc("save_run_idempotent", params: params).execute()
    }
}

private struct ProfileIdentity: Decodable { let id: UUID; let display_name: String }
private struct AccountDeletionResult: Decodable { let deleted: Bool }
private enum AccountDeletionError: Error { case failed }
private enum ProfileError: LocalizedError {
    case invalidName
    var errorDescription: String? { "Enter a name between 1 and 80 characters." }
}
private struct NewProfile: Encodable { let id: UUID; let display_name: String }

private struct SaveRunParameters: Encodable {
    let p_run_id: UUID
    let p_started_at: Date
    let p_ended_at: Date
    let p_active_seconds: Int
    let p_distance_meters: Double
    let p_program_id: String
    let p_program_version: Int
    let p_session_id: String
    let p_session_completed: Bool
    let p_points: [RunLocation]
}

struct RootView: View {
    @State private var session = AppSession()
    var body: some View {
        Group {
            if session.loading { ProgressView("Getting ready…") }
            else if session.signedIn && session.profileLoadFailed {
                ContentUnavailableView {
                    Label("Couldn't load your account", systemImage: "wifi.exclamationmark")
                } description: {
                    Text("Check your connection and try again.")
                } actions: {
                    Button(session.profileLoading ? "Trying again…" : "Try again") { Task { await session.loadProfile() } }
                        .disabled(session.profileLoading)
                    Button("Sign out") { Task { await session.signOut() } }
                }
            }
            else if session.signedIn && session.needsOnboarding { OnboardingView(session: session) }
            else if session.signedIn { AppTabs().environment(session) }
            else { WelcomeView(session: session) }
        }.task { await session.restore() }
        .onReceive(NotificationCenter.default.publisher(for: ASAuthorizationAppleIDProvider.credentialRevokedNotification)) { _ in
            Task { await session.signOut() }
        }
        .sheet(isPresented: $session.accountDeleted) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Label("Your account is deleted", systemImage: "checkmark.circle.fill")
                            .font(.title2.bold())
                        Text("Your French Fried profile, saved runs, routes, progress, and crew membership have been removed.")
                        Text("One last step with Apple")
                            .font(.headline)
                        Text("To disconnect French Fried from your Apple Account, open Settings → your name → Sign in with Apple → French Fried, then choose Delete. This removes Apple's sign-in connection; your French Fried data has already been deleted.")
                        Link("Apple's step-by-step instructions", destination: URL(string: "https://support.apple.com/en-us/102571")!)
                        Button("Done") { session.accountDeleted = false }
                            .buttonStyle(.borderedProminent)
                    }.padding(24)
                }.navigationTitle("Account deleted")
            }
        }
    }
}
