import Foundation

/// Emits at most one cue for the latest phase; never replays crossed phases.
public struct PhaseCuePolicy: Sendable {
    private var lastKey: Int?
    public init() {}

    public mutating func next(engine: IntervalEngine, isRunning: Bool) -> String? {
        guard isRunning else { return nil }
        let key = engine.state == .completed ? engine.session.phases.count : engine.phaseIndex
        guard key != lastKey else { return nil }
        lastKey = key
        guard let phase = engine.currentPhase else { return "Session complete. Pause to finish and save your run." }
        switch phase.kind {
        case .warmUp: return "Start your warm-up walk."
        case .run: return "Time to run. Go at your own pace."
        case .walk: return "Time to walk."
        case .coolDown: return "Time for your cool-down walk."
        }
    }
}
