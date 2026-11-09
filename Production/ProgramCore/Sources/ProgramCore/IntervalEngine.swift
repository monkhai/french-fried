import Foundation

/// A deterministic interval clock. Pass a monotonic timestamp, such as
/// ProcessInfo.processInfo.systemUptime, to every method. No timers or GPS live here.
public struct IntervalEngine: Sendable {
    public enum State: Equatable, Sendable {
        case paused
        case running
        case completed
    }

    public let session: TrainingSession
    public private(set) var state: State = .paused
    public private(set) var phaseIndex: Int = 0
    public private(set) var elapsedInPhase: TimeInterval = 0
    public private(set) var activeElapsed: TimeInterval = 0
    private var lastTimestamp: TimeInterval?

    public init(session: TrainingSession) throws {
        try session.validate()
        self.session = session
    }

    public var currentPhase: SessionPhase? {
        state == .completed ? nil : session.phases[phaseIndex]
    }

    public var remainingInPhase: TimeInterval {
        guard let phase = currentPhase else { return 0 }
        return max(0, TimeInterval(phase.durationSeconds) - elapsedInPhase)
    }

    /// Resumes from the current phase. The caller owns scheduling update calls.
    public mutating func resume(at timestamp: TimeInterval) {
        guard state == .paused, timestamp.isFinite else { return }
        state = .running
        lastTimestamp = timestamp
    }

    /// Advances through any number of phases, including after a delayed update.
    public mutating func update(at timestamp: TimeInterval) {
        guard state == .running, let last = lastTimestamp, timestamp.isFinite, timestamp >= last else { return }
        var elapsed = timestamp - last
        lastTimestamp = timestamp
        while elapsed > 0, state == .running {
            let remaining = remainingInPhase
            let consumed = min(elapsed, remaining)
            elapsedInPhase += consumed
            activeElapsed += consumed
            elapsed -= consumed
            if elapsedInPhase >= TimeInterval(session.phases[phaseIndex].durationSeconds) {
                if phaseIndex + 1 == session.phases.count {
                    state = .completed
                    lastTimestamp = nil
                } else {
                    phaseIndex += 1
                    elapsedInPhase = 0
                }
            }
        }
    }

    /// Accounts for time up to the tap, then freezes the clock.
    public mutating func pause(at timestamp: TimeInterval) {
        guard state == .running, let last = lastTimestamp,
              timestamp.isFinite, timestamp >= last else { return }
        update(at: timestamp)
        guard state == .running else { return }
        state = .paused
        lastTimestamp = nil
    }
}
