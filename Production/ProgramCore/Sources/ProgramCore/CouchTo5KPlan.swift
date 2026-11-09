import Foundation

/// Immutable timing edition. See ATTRIBUTION.md before displaying this content.
public enum CouchTo5KPlan {
    public static let attribution = "Contains public sector information licensed under the Open Government Licence v3.0."
    public static let licenseURL = URL(string: "https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/")!
    public static let contentDate = "2026-11-01"

    public static let program = TrainingProgram(id: "couch-to-5k", version: 1, sessions: makeSessions())

    private static func makeSessions() -> [TrainingSession] {
        // Seconds, alternating run and walk, starting and ending with run.
        let week1 = Array(repeating: [60, 90], count: 7).flatMap { $0 } + [60]
        let week2 = Array(repeating: [90, 120], count: 5).flatMap { $0 } + [90]
        let week3 = [90, 90, 180, 180, 90, 90, 180]
        let week4 = [180, 90, 300, 150, 180, 90, 300]
        let weeks: [[[Int]]] = [
            [week1, week1, week1],
            [week2, week2, week2],
            [week3, week3, week3],
            [week4, week4, week4],
            [[300, 180, 300, 180, 300], [480, 300, 480], [1200]],
            [[300, 180, 480, 180, 300], [600, 180, 600], [1500]],
            [[1500], [1500], [1500]],
            [[1680], [1680], [1680]],
            [[1800], [1800], [1800]]
        ]
        return weeks.enumerated().flatMap { weekIndex, runs in
            runs.enumerated().map { runIndex, durations in
                let middle = durations.enumerated().map { index, seconds in
                    SessionPhase(kind: index.isMultiple(of: 2) ? .run : .walk, durationSeconds: seconds)
                }
                return TrainingSession(
                    id: "w\(weekIndex + 1)-r\(runIndex + 1)",
                    week: weekIndex + 1, number: runIndex + 1,
                    phases: [SessionPhase(kind: .warmUp, durationSeconds: 300)]
                        + middle + [SessionPhase(kind: .coolDown, durationSeconds: 300)]
                )
            }
        }
    }
}

public extension TrainingSession {
    var totalDurationSeconds: Int { phases.reduce(0) { $0 + $1.durationSeconds } }
    var runningDurationSeconds: Int {
        phases.filter { $0.kind == .run }.reduce(0) { $0 + $1.durationSeconds }
    }
}
