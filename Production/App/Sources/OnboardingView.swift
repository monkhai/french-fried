import SwiftUI

struct OnboardingView: View {
    let session: AppSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var name = ""
    @State private var step: Step = .name
    @State private var saving = false
    @State private var error: String?
    @State private var showGroup = false
    @State private var initialized = false
    @FocusState private var nameFocused: Bool
    private let cream = Color(red: 0.98, green: 0.96, blue: 0.92)
    private enum Step: Int { case name, group, ready }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Text("LET’S GET YOU MOVING").font(.caption.weight(.heavy)).tracking(1.5)
                        Spacer()
                        Text("\(step.rawValue + 1) of 3")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        ForEach(0..<3) { index in
                            Capsule().fill(index <= step.rawValue ? Color.orange : Color.orange.opacity(0.15))
                                .frame(height: 4)
                        }
                    }.accessibilityLabel("Setup step \(step.rawValue + 1) of 3")
                    Group {
                        if step == .name { nameStep }
                        else if step == .group { groupStep }
                        else { readyStep }
                    }
                    .id(step)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .opacity.combined(with: .offset(x: 24)),
                        removal: .opacity.combined(with: .offset(x: -16))))
                }.padding(24).id("onboardingTop")
            }
            .onChange(of: step) { _, _ in proxy.scrollTo("onboardingTop", anchor: .top) }
            .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.92), value: step)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(cream.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { actions.padding(24).background(cream) }
            .task {
                guard !initialized else { return }
                initialized = true
                name = session.displayName.isEmpty ? session.suggestedName : session.displayName
            }
            .sheet(isPresented: $showGroup) {
                GroupView().environment(session)
                    .safeAreaInset(edge: .bottom) {
                        Button("Continue") { showGroup = false; step = .ready }
                            .buttonStyle(OnboardingButtonStyle()).padding(24).background(.regularMaterial)
                    }
            }
        }.tint(.orange)
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingPotato().frame(height: 150)
                .frame(maxWidth: .infinity).accessibilityHidden(true)
            Text("First, a name.").font(.largeTitle.bold())
            Text("A little introduction before your first step. Choose a name for your profile—you can change it anytime.").foregroundStyle(.secondary)
            TextField("Your name", text: $name)
                .textContentType(.nickname).textInputAutocapitalization(.words)
                .autocorrectionDisabled().focused($nameFocused).submitLabel(.continue)
                .onSubmit { if validName && !saving { Task { await saveName() } } }
                .padding(16).background(.white, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel("Display name")
            if trimmedName.unicodeScalars.count > 80 {
                Text("Keep your name to 80 characters or fewer.").font(.footnote).foregroundStyle(.red)
            }
            if let error { Text(error).font(.footnote).foregroundStyle(.red).accessibilityAddTraits(.updatesFrequently) }
        }
    }

    private var groupStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: -12) {
                ForEach(0..<3) { index in
                    Image(systemName: index == 1 ? "figure.run" : "person.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(index == 1 ? Color.white : Color.orange)
                        .frame(width: 70, height: 70)
                        .background(index == 1 ? Color.orange : Color.white, in: Circle())
                        .overlay(Circle().stroke(cream, lineWidth: 4))
                        .offset(y: index == 1 ? -8 : 4)
                }
            }.frame(maxWidth: .infinity).padding(.vertical, 24).accessibilityHidden(true)
            Text("Better with a little backup.").font(.largeTitle.bold())
            Text("Create a crew or join with an invite code. See your friends’ saved runs and progress, even when you head out at different times.").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                Label("Progress together. Routes just for you.", systemImage: "lock.fill").font(.subheadline.weight(.semibold))
                Text("Your crew sees your name and run summaries. Your route map stays private.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 20))
            Text("Flying solo? You can join a crew later from the Group tab.").font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var readyStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            OnboardingPotato().frame(height: 110).frame(maxWidth: .infinity).accessibilityHidden(true)
            Text("You’re in, \(name.trimmingCharacters(in: .whitespacesAndNewlines)).").font(.largeTitle.bold())
            Text("No perfect pace required. Just start where you are.").foregroundStyle(.secondary)
            detail("Walk, then run", "Follow timed walking and running intervals. Start with your next session in Runs.", icon: "figure.walk")
            detail("Go at your pace", "The timer guides each interval. Pause when you need a breather, then resume when you’re ready.", icon: "pause.circle")
            detail("Save your small wins", "Finish and save your run to see its time, distance, and private route in History.", icon: "clock.arrow.circlepath")
            Text("We’ll ask for location when you start tracking, so your route and distance can be recorded.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func detail(_ title: String, _ subtitle: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title2).foregroundStyle(.orange).frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var actions: some View {
        VStack(spacing: 12) {
            if step == .name {
                Button(saving ? "Saving…" : "Continue") { Task { await saveName() } }
                    .buttonStyle(OnboardingButtonStyle()).disabled(saving || !validName)
            } else if step == .group {
                Button("Find your crew") { showGroup = true }.buttonStyle(OnboardingButtonStyle())
                Button("Continue solo") { step = .ready }.frame(maxWidth: .infinity).padding(.vertical, 8)
            } else {
                Button("Let’s get moving") { session.finishOnboarding() }.buttonStyle(OnboardingButtonStyle())
            }
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var validName: Bool { !trimmedName.isEmpty && trimmedName.unicodeScalars.count <= 80 }
    private func saveName() async {
        guard validName, !saving else { return }
        saving = true; error = nil; nameFocused = false
        defer { saving = false }
        do {
            if session.displayName.isEmpty { try await session.createProfile(name: trimmedName) }
            else { try await session.updateProfile(name: trimmedName) }
            step = .group
        } catch { self.error = "Couldn’t save your name. Check your connection and try again." }
    }
}

private struct OnboardingButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity).padding(16)
            .background(.orange.opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.35), in: Capsule())
            .foregroundStyle(.black.opacity(enabled ? 1 : 0.5))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.9), value: configuration.isPressed)
    }
}
