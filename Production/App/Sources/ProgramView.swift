import SwiftUI
import ProgramCore

struct ProgramView: View {
    @Environment(AppSession.self) private var appSession
    @State private var progress: [SessionProgress] = []
    @State private var progressLoaded = false
    @State private var progressError = false
    @State private var refreshingProgress = false
    @State private var expandedWeek: Int? = 1
    @State private var selectedSession: TrainingSession?
    private let cream = Color(red: 0.98, green: 0.96, blue: 0.92)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("One run at a time.").font(.title2.bold())
                        Text("Nine weeks to 30 minutes of running. Choose a session below, and repeat whenever you want.")
                            .foregroundStyle(.secondary)
                        Text("Take a rest day between runs. Every session includes a 5-minute warm-up walk and a 5-minute cool-down walk.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text("Go at a comfortable pace. If you have concerns about your health, speak with a clinician before starting.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 24))
                    if progressError {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your progress couldn't load.").font(.headline)
                            Text("You can still choose a run. Check your connection and retry to see completed sessions.").font(.subheadline).foregroundStyle(.secondary)
                            Button("Try again") { Task { await loadProgress() } }.disabled(refreshingProgress)
                        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 20))
                    } else if progressLoaded {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(nextSession == nil ? "You did it. All 27 runs." : "Your next little victory")
                                .font(.headline)
                            Text("\(completedIDs.count) of 27 sessions complete")
                                .font(.subheadline).foregroundStyle(.secondary)
                            if let next = nextSession {
                                NavigationLink { sessionDetail(next) } label: {
                                    Label("Week \(next.week) · Run \(next.number)", systemImage: "arrow.right.circle.fill")
                                        .font(.headline).foregroundStyle(.orange)
                                }
                            } else {
                                Text("Nine weeks complete. Repeat a favourite session whenever you're ready.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 20))
                    } else {
                        ProgressView("Loading your progress…").frame(maxWidth: .infinity)
                    }
                    ForEach(1...9, id: \.self) { week in
                        VStack(alignment: .leading, spacing: 0) {
                            Button {
                                expandedWeek = expandedWeek == week ? nil : week
                            } label: {
                                HStack(spacing: 14) {
                                    Text("\(week)").font(.headline).frame(width: 44, height: 44)
                                        .background(cream, in: Circle())
                                    Text("Week \(week)").font(.headline)
                                    Spacer()
                                    if progressLoaded {
                                        Text("\(progress.filter { $0.week == week && $0.completed }.count)/3")
                                            .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                                    }
                                    Image(systemName: expandedWeek == week ? "chevron.up" : "chevron.down")
                                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                }.padding(14).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .accessibilityValue(expandedWeek == week ? "Expanded" : "Collapsed")
                            if expandedWeek == week {
                                ForEach(CouchTo5KPlan.program.sessions.filter { $0.week == week }, id: \.id) { session in
                                    NavigationLink {
                                        sessionDetail(session)
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("Run \(session.number)").font(.headline)
                                                Text(duration(session.totalDurationSeconds) + " total")
                                                    .font(.subheadline).foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            if completedIDs.contains(session.id) {
                                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                                    .accessibilityLabel("Completed")
                                            }
                                            Image(systemName: "chevron.right").font(.caption.bold())
                                        }.padding(18).contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                }
                            }
                        }.background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 20))
                    }
                    attribution
                }.padding(20)
            }
            .background(cream.ignoresSafeArea())
            .navigationTitle("Your runs")
            .fullScreenCover(item: $selectedSession, onDismiss: { Task { await loadProgress() } }) { TrackingView(trainingSession: $0) }
            .task { await loadProgress() }
            .refreshable { await loadProgress() }
        }
    }

    private func sessionDetail(_ session: TrainingSession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(duration(session.totalDurationSeconds) + " · including walks")
                    .font(.title3.bold())
                Text("Run at your own pace. You can pause at any time, and repeat this session whenever you need.")
                    .foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    ForEach(Array(session.phases.enumerated()), id: \.offset) { index, phase in
                        HStack {
                            Image(systemName: phase.kind == .run ? "figure.run" : "figure.walk")
                                .foregroundStyle(.orange).frame(width: 28)
                            Text(phaseLabel(phase.kind))
                            Spacer()
                            Text(duration(phase.durationSeconds)).monospacedDigit()
                        }.padding(.horizontal, 14).padding(.vertical, 8)
                        if index + 1 < session.phases.count { Divider().padding(.horizontal, 14) }
                    }
                }.background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 20))
                Button { selectedSession = session } label: {
                    Label(completedIDs.contains(session.id) ? "Repeat this run" : "Start this run", systemImage: "play.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(16)
                        .background(.orange, in: Capsule()).foregroundStyle(.black)
                }
                attribution
            }.padding(20)
        }.background(cream.ignoresSafeArea())
            .navigationTitle("Week \(session.week) · Run \(session.number)")
    }

    private var completedIDs: Set<String> { Set(progress.filter(\.completed).map(\.session_id)) }
    private var nextSession: TrainingSession? {
        CouchTo5KPlan.program.sessions.first { !completedIDs.contains($0.id) }
    }

    @MainActor private func loadProgress() async {
        guard !refreshingProgress else { return }
        refreshingProgress = true
        defer { refreshingProgress = false }
        do {
            let rows: [SessionProgress] = try await appSession.client.rpc("list_my_program_progress").execute().value
            guard rows.count == CouchTo5KPlan.program.sessions.count else { throw ProgressLoadError.incomplete }
            let firstLoad = !progressLoaded
            progress = rows
            progressLoaded = true
            progressError = false
            if firstLoad { expandedWeek = nextSession?.week ?? 9 }
        } catch { progressError = true }
    }

    private var attribution: some View {
        Link(CouchTo5KPlan.attribution, destination: CouchTo5KPlan.licenseURL)
            .font(.footnote).foregroundStyle(.secondary)
    }

    private func duration(_ seconds: Int) -> String {
        seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds / 60) min \(seconds % 60) sec"
    }

    private func phaseLabel(_ kind: PhaseKind) -> String {
        switch kind {
        case .warmUp: "Warm-up walk"
        case .run: "Run"
        case .walk: "Walk"
        case .coolDown: "Cool-down walk"
        }
    }
}


private struct SessionProgress: Decodable {
    let session_id: String
    let week: Int
    let run_number: Int
    let completed: Bool
}
private enum ProgressLoadError: Error { case incomplete }
