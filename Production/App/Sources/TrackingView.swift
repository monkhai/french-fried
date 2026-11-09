import SwiftUI
import MapKit
import RunTracking
import ProgramCore

private struct RunWeekProgress: Decodable {
    let week: Int
    let completed: Bool
}

struct TrackingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(RunCuePreferences.voiceKey) private var voiceEnabled = false
    @AppStorage(RunCuePreferences.hapticsKey) private var hapticsEnabled = false
    @Environment(AppSession.self) private var session
    @State private var tracker = RunTracker()
    @State private var mapPosition: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)
    @State private var followingLocation = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmingFinish = false
    @State private var finishedRun: RecordedRun?
    @State private var runID = UUID()
    @State private var saving = false
    @State private var saved = false
    @State private var saveError: String?
    @State private var confirmingDiscard = false
    @State private var cuePolicy = PhaseCuePolicy()
    @State private var cuePlayer = RunCuePlayer()
    @State private var runActivity = RunActivityController()
    let trainingSession: TrainingSession?
    let recovery: RunRecovery?
    @State private var intervals: IntervalEngine?
    @State private var recoveryError = false

    init(trainingSession: TrainingSession? = nil, recovery: RunRecovery? = nil) {
        self.trainingSession = trainingSession
        self.recovery = recovery
        _runID = State(initialValue: recovery?.id ?? UUID())
        _finishedRun = State(initialValue: recovery?.finishedRun)
        var restoredIntervals = trainingSession.flatMap { try? IntervalEngine(session: $0) }
        if let elapsed = recovery?.checkpoint?.activeSeconds ?? recovery?.finishedRun?.activeSeconds {
            restoredIntervals?.resume(at: 0)
            restoredIntervals?.update(at: elapsed)
            restoredIntervals?.pause(at: elapsed)
        }
        _intervals = State(initialValue: restoredIntervals)
    }

    var body: some View {
        VStack(spacing: 0) {
        Map(position: $mapPosition, interactionModes: [.pan, .zoom, .rotate]) {
                if tracker.locations.count > 1 {
                    // A pause can create multiple independent route segments.
                    ForEach(Array(Set(tracker.locations.map(\.segment))).sorted(), id: \.self) { segment in
                        let coordinates = tracker.locations.filter { $0.segment == segment }.map {
                            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                        }
                        MapPolyline(coordinates: coordinates).stroke(.orange, lineWidth: 5)
                    }
                }
                UserAnnotation()
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { _ in
            followingLocation = false
        })
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .topTrailing) {
            Button {
                followingLocation = true
                centerOnLocation()
            } label: {
                Label(followingLocation ? "Following" : "Recenter", systemImage: followingLocation ? "location.fill" : "location")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(.regularMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("run.recenter")
            .accessibilityHint("Centers the map on your location and follows your movement")
            .padding(16)
        }
            VStack(alignment: .leading, spacing: 16) {
                if let finishedRun {
                    Text("Run finished").font(.title2.bold())
                    Text(String(format: "%.2f km · %@", finishedRun.distanceMeters / 1_000, clock(finishedRun.activeSeconds)))
                    if saved {
                        Text("Saved to your account.").font(.subheadline).foregroundStyle(.secondary)
                        Button("Done", systemImage: "checkmark") { dismiss() }
                            .buttonStyle(RunPrimaryButtonStyle())
                    } else {
                        Text("Save this run to your account.").font(.subheadline).foregroundStyle(.secondary)
                        if let saveError { Text(saveError).font(.footnote).foregroundStyle(.red) }
                        Button(saving ? "Saving…" : "Save run") {
                            saving = true
                            Task {
                                do {
                                    let completedWeekBefore = await completedWeek()
                                    try await session.save(finishedRun, id: runID, trainingSession: trainingSession, sessionCompleted: intervals?.state == .completed)
                                    if let owner = session.recoveryOwnerID { RunRecoveryStore.clear(id: runID, owner: owner) }
                                    saved = true
                                    saveError = nil
                                    let completedWeekAfter = await completedWeek()
                                    let newlyCompleted = completedWeekBefore == false && completedWeekAfter == true
                                    cuePlayer.play(.runSaved, voice: voiceEnabled, haptics: hapticsEnabled, followedBy: newlyCompleted ? .weekCompleted : nil)
                                }
                                catch { saveError = "Couldn't confirm the save. Check your connection and try again." }
                                saving = false
                            }
                        }.disabled(saving).buttonStyle(RunPrimaryButtonStyle())
                        Button("Discard run", role: .destructive) { confirmingDiscard = true }.disabled(saving)
                    }
                } else {
                    HStack {
                        Label(tracker.state == .paused ? "Paused" : tracker.state == .idle ? "Ready to run?" : "Recording",
                              systemImage: tracker.state == .paused ? "pause.circle.fill" : "figure.run")
                            .font(.title2.bold())
                    }
                    if tracker.state != .idle, let intervals {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("WEEK \(intervals.session.week) · RUN \(intervals.session.number)").font(.caption.bold()).foregroundStyle(.secondary)
                            if let phase = intervals.currentPhase {
                                HStack {
                                    Text(phaseTitle(phase.kind)).font(.headline)
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(clock(intervals.remainingInPhase.rounded(.up)))
                                            .font(.title.bold().monospacedDigit())
                                        Text("remaining").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                if intervals.phaseIndex + 1 < intervals.session.phases.count {
                                    let next = intervals.session.phases[intervals.phaseIndex + 1]
                                    Text("Next: \(phaseTitle(next.kind))").font(.subheadline).foregroundStyle(.secondary)
                                }
                            } else {
                                Text("Session complete. Pause to finish and save your run.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    HStack(alignment: .top, spacing: 12) {
                        metric(String(format: "%.2f", tracker.distanceMeters / 1_000), label: "Distance · km")
                        metric(clock(tracker.elapsedSeconds), label: "Active time")
                        metric(tracker.distanceMeters >= 10 ? tracker.averagePaceSecondsPerKilometer.map(clock) ?? "—" : "—", label: "Avg pace / km")
                    }
                    if tracker.state == .paused {
                        Text(recovery == nil ? "Tracking and the timer are paused." : "Run recovered. Resume when you're ready; time away wasn't recorded.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else if tracker.state == .running && tracker.locations.isEmpty && tracker.issue == nil {
                        Label("Finding your location. The timer is running.", systemImage: "location")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let issue = tracker.issue { Text(issue).font(.subheadline).foregroundStyle(.secondary) }
                    if recoveryError { Text("Couldn't save this run on your device. Keep the app open and try again.").font(.caption).foregroundStyle(.red) }
                    if tracker.locationPermissionDenied || !tracker.preciseLocationEnabled {
                        Button("Open location settings", systemImage: "gearshape") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }
                    if tracker.state == .idle, let trainingSession {
                        Text("Week \(trainingSession.week) · Run \(trainingSession.number)").font(.headline)
                        Text("Start with a 5-minute warm-up walk. Follow each interval at your own pace.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if trainingSession != nil {
                        Link(CouchTo5KPlan.attribution, destination: CouchTo5KPlan.licenseURL)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if tracker.state == .idle {
                        Button(tracker.waitingForPermission ? "Waiting for location…" : "Start run", systemImage: "play.fill") { tracker.start() }
                            .disabled(tracker.waitingForPermission)
                            .buttonStyle(RunPrimaryButtonStyle())
                        Button("Back") { dismiss() }.frame(maxWidth: .infinity)
                    } else {
                        ActiveRunControls(paused: tracker.state == .paused) {
                            if tracker.state == .running { tracker.pause() } else { tracker.resume() }
                        } onFinish: {
                            guard tracker.state == .paused else { return }
                            confirmingFinish = true
                        }
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(24).background(.background, in: RoundedRectangle(cornerRadius: 28))
            .padding(12)
        }
        .onAppear {
            if let recovery {
                runActivity.endActivitiesLeftByPreviousLaunch()
                if let checkpoint = recovery.checkpoint, recovery.finishedRun == nil { tracker.restore(checkpoint) }
            }
            tracker.prepareLocation()
        }
        .onChange(of: mapPosition.positionedByUser) { _, byUser in
            if byUser { followingLocation = false }
        }
        .interactiveDismissDisabled((tracker.state != .idle || finishedRun != nil) && !saved)
        .confirmationDialog("Finish this run?", isPresented: $confirmingFinish, titleVisibility: .visible) {
            Button("Finish run") {
                if let run = tracker.finish() {
                    intervals?.update(at: run.activeSeconds)
                    intervals?.pause(at: run.activeSeconds)
                    finishedRun = run
                    saveRecovery()
                }
            }
            Button("Keep paused", role: .cancel) { }
        }
        .confirmationDialog("Discard this run?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard run", role: .destructive) { if let owner = session.recoveryOwnerID { RunRecoveryStore.clear(id: runID, owner: owner) }; dismiss() }
            Button("Keep run", role: .cancel) { }
        } message: { Text("If a previous save could not be confirmed, it may already be in your history.") }
        // Use the tracker's accumulated active time as the shared clock so that
        // location permission delays and automatic pauses cannot start the intervals.
        .onChange(of: tracker.state) { previous, state in
            switch state {
            case .running:
                intervals?.resume(at: tracker.elapsedSeconds)
                if previous == .paused {
                    cuePlayer.play(.resume, voice: voiceEnabled, haptics: hapticsEnabled)
                } else if trainingSession == nil {
                    cuePlayer.play(.freeRunStart, voice: voiceEnabled, haptics: hapticsEnabled)
                } else {
                    emitCue()
                }
            case .paused:
                intervals?.pause(at: tracker.elapsedSeconds)
                cuePlayer.stop()
                if previous != .idle { cuePlayer.play(.pause, voice: voiceEnabled, haptics: hapticsEnabled) }
            case .idle, .finished: cuePlayer.stop()
            }
            saveRecovery()
            updateRunActivity()
        }
        .onChange(of: tracker.elapsedSeconds) { _, elapsed in
            intervals?.update(at: elapsed)
            saveRecovery()
            emitCue()
            updateRunActivity()
        }
        .onChange(of: tracker.locations.count) { _, _ in saveRecovery() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { tracker.prepareLocation() }
            if phase == .active, tracker.state == .running {
                // Catch up to the latest phase after a suspension, without replaying older cues.
                intervals?.update(at: tracker.recorder.elapsed())
                emitCue()
                updateRunActivity()
            }
        }
        .onChange(of: voiceEnabled) { _, enabled in if !enabled { cuePlayer.stop() } }
        .onDisappear { cuePlayer.stop(); runActivity.end() }
    }

    private func saveRecovery() {
        guard !saved, let owner = session.recoveryOwnerID else { return }
        let checkpoint = tracker.recorder.checkpoint()
        guard checkpoint != nil || finishedRun != nil else { return }
        do {
            try RunRecoveryStore.save(RunRecovery(id: runID, owner: owner, sessionID: trainingSession?.id,
                                                  checkpoint: checkpoint, finishedRun: finishedRun))
            recoveryError = false
        } catch {
            recoveryError = true
        }
    }

    private func centerOnLocation() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.6)) {
            mapPosition = .userLocation(followsHeading: true, fallback: .automatic)
        }
    }

    private func completedWeek() async -> Bool? {
        guard let trainingSession, intervals?.state == .completed else { return nil }
        do {
            let rows: [RunWeekProgress] = try await session.client.rpc("list_my_program_progress").execute().value
            let week = rows.filter { $0.week == trainingSession.week }
            guard week.count == 3 else { return nil }
            return week.allSatisfy(\.completed)
        } catch {
            return nil
        }
    }

    private func emitCue() {
        guard let intervals, let message = cuePolicy.next(engine: intervals,
            isRunning: tracker.state == .running) else { return }
        let cue: RunCuePlayer.Cue
        switch message {
        case "Start your warm-up walk.": cue = .warmUp
        case "Time to run. Go at your own pace.": cue = .run
        case "Time to walk.": cue = .walk
        case "Time for your cool-down walk.": cue = .coolDown
        default: cue = .sessionComplete
        }
        cuePlayer.play(cue, voice: voiceEnabled, haptics: hapticsEnabled)
    }

    private func updateRunActivity() {
        guard tracker.state == .running || tracker.state == .paused else {
            runActivity.end()
            return
        }
        let paused = tracker.state == .paused
        if let intervals {
            let complete = intervals.state == .completed
            let phase = intervals.currentPhase.map { phaseTitle($0.kind) } ?? "Complete"
            let nextIndex = intervals.phaseIndex + 1
            let next = nextIndex < intervals.session.phases.count
                ? phaseTitle(intervals.session.phases[nextIndex].kind) : nil
            let phases = intervals.session.phases
            let runCount = phases.filter { $0.kind == .run }.count
            let runsSoFar = phases.prefix(intervals.phaseIndex + 1).filter { $0.kind == .run }.count
            let showsRound = intervals.currentPhase.map { $0.kind == .run || $0.kind == .walk } ?? false
            runActivity.update(title: "Week \(intervals.session.week) · Run \(intervals.session.number)",
                               phase: phase, next: next, remaining: intervals.remainingInPhase,
                               paused: paused, complete: complete, countUp: false,
                               key: "\(intervals.phaseIndex)-\(paused)-\(complete)",
                               intervalIndex: intervals.phaseIndex,
                               intervalKinds: phases.map { phaseTitle($0.kind) },
                               roundNumber: showsRound && runsSoFar > 0 ? runsSoFar : nil,
                               roundCount: runCount > 0 ? runCount : nil)
        } else {
            runActivity.update(title: "Free run", phase: "Run", next: nil,
                               remaining: tracker.elapsedSeconds, paused: paused, complete: false,
                               countUp: true, key: "free-\(paused)")
        }
    }

    private func metric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.title3.bold()).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func clock(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return "—" }
        let value = Int(seconds)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    private func phaseTitle(_ kind: PhaseKind) -> String {
        switch kind {
        case .warmUp: "Warm up"
        case .run: "Run"
        case .walk: "Walk"
        case .coolDown: "Cool down"
        }
    }
}


/// Explicit foreground prevents the app's orange tint from hiding labels on orange.
private struct RunPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.titleAndIcon)
            .font(.headline)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 12)
            .background(.orange.opacity(configuration.isPressed ? 0.75 : 1), in: Capsule())
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.5)
    }
}


/// The approved control keeps both glass surfaces alive so the capsule can
/// merge into the fixed finish circle without moving its hit target.
private struct ActiveRunControls: View {
    let paused: Bool
    let onTogglePause: () -> Void
    let onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNamespace

    var body: some View {
        GeometryReader { geometry in
            let capsuleWidth = max(56, geometry.size.width - (paused ? 72 : 0))
            GlassEffectContainer(spacing: 8) {
                ZStack(alignment: .leading) {
                    Button(action: onFinish) {
                        Image(systemName: "stop.fill")
                            .font(.headline)
                            .blur(radius: reduceMotion || paused ? 0 : 12)
                            .opacity(paused ? 1 : 0)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: paused)
                            .frame(width: 56, height: 56)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.black)
                    .glassEffect(.regular.tint(.orange).interactive(), in: .circle)
                    .glassEffectID("finish", in: glassNamespace)
                    .offset(x: max(0, geometry.size.width - 56))
                    .allowsHitTesting(paused)
                    .accessibilityLabel("Finish run")
                    .accessibilityHint("Opens confirmation before ending your run")
                    .accessibilityIdentifier("run.finish")
                    .accessibilityHidden(!paused)
                    .disabled(!paused)

                    Button(action: onTogglePause) {
                        Color.clear
                            .frame(width: capsuleWidth, height: 56)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.black)
                    .glassEffect(.regular.tint(.orange).interactive(), in: .capsule)
                    .glassEffectID("pauseResume", in: glassNamespace)
                    .accessibilityLabel(paused ? "Resume" : "Pause")
                    .accessibilityIdentifier("run.pauseResume")
                }
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 8) {
                    Image(systemName: paused ? "play.fill" : "pause.fill")
                        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                        .frame(width: 22, height: 22)
                    Text(paused ? "Resume" : "Pause")
                        .contentTransition(.identity)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(width: 70, alignment: .leading)
                }
                .font(.headline).foregroundStyle(.black)
                .frame(width: 100, height: 56)
                .geometryGroup()
                .offset(x: (capsuleWidth - 100) / 2)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.68), value: paused)
        }
        .frame(height: 56)
    }
}
