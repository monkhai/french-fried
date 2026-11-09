import ActivityKit
import Foundation

struct RunActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: String
        var nextPhase: String?
        var endsAt: Date?
        var remaining: Int
        var paused: Bool
        var complete: Bool
        var countUp: Bool
        var intervalIndex: Int?
        var intervalKinds: [String]?
        var roundNumber: Int?
        var roundCount: Int?
    }
    var title: String
}
