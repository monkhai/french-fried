import ActivityKit
import Foundation

@MainActor
final class RunActivityController {
    private var activity: Activity<RunActivityAttributes>?
    private var lastKey: String?

    /// A force-quit leaves the system activity alive. End only the old snapshot;
    /// recovery immediately creates a fresh paused activity for this run.
    func endActivitiesLeftByPreviousLaunch() {
        let oldActivities = Activity<RunActivityAttributes>.activities
        Task {
            for old in oldActivities { await old.end(nil, dismissalPolicy: .immediate) }
        }
    }

    func update(title: String, phase: String, next: String?, remaining: TimeInterval, paused: Bool, complete: Bool, countUp: Bool, key: String, intervalIndex: Int? = nil, intervalKinds: [String]? = nil, roundNumber: Int? = nil, roundCount: Int? = nil) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, key != lastKey else { return }
        let seconds = max(0, Int(remaining.rounded(.up)))
        let state = RunActivityAttributes.ContentState(phase: phase, nextPhase: next,
            endsAt: paused || complete ? nil : Date().addingTimeInterval(countUp ? -TimeInterval(seconds) : TimeInterval(seconds)),
            remaining: seconds, paused: paused, complete: complete, countUp: countUp,
            intervalIndex: intervalIndex, intervalKinds: intervalKinds, roundNumber: roundNumber, roundCount: roundCount)
        let content = ActivityContent(state: state, staleDate: nil)
        if let activity {
            lastKey = key
            Task { await activity.update(content) }
        } else {
            do {
                activity = try Activity.request(attributes: RunActivityAttributes(title: title), content: content, pushType: nil)
                lastKey = key
            } catch {
                // Live Activities are optional; tracking must continue if the system declines one.
                lastKey = key
                print("Could not start Live Activity: \(error)")
            }
        }
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        lastKey = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
