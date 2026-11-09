import Foundation

/// A published version should never be edited after a run refers to it.
public struct TrainingProgram: Codable, Equatable, Sendable {
    public let id: String
    public let version: Int
    public let sessions: [TrainingSession]

    public init(id: String, version: Int, sessions: [TrainingSession]) {
        self.id = id
        self.version = version
        self.sessions = sessions
    }

    /// Call when loading program content. It does not prescribe a particular schedule.
    public func validate() throws {
        guard !id.isEmpty, version > 0, !sessions.isEmpty else { throw ProgramError.invalidProgram }
        var sessionIDs = Set<String>()
        var slots = Set<String>()
        for session in sessions {
            try session.validate()
            guard sessionIDs.insert(session.id).inserted,
                  slots.insert("\(session.week):\(session.number)").inserted else {
                throw ProgramError.duplicateSession
            }
        }
    }
}

public struct TrainingSession: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let week: Int
    public let number: Int
    public let phases: [SessionPhase]

    public init(id: String, week: Int, number: Int, phases: [SessionPhase]) {
        self.id = id
        self.week = week
        self.number = number
        self.phases = phases
    }

    public func validate() throws {
        guard !id.isEmpty, (1...9).contains(week), (1...3).contains(number),
              !phases.isEmpty, phases.allSatisfy({ $0.durationSeconds > 0 }) else {
            throw ProgramError.invalidSession
        }
    }
}

public struct SessionPhase: Codable, Equatable, Sendable {
    public let kind: PhaseKind
    public let durationSeconds: Int

    public init(kind: PhaseKind, durationSeconds: Int) {
        self.kind = kind
        self.durationSeconds = durationSeconds
    }
}

public enum PhaseKind: String, Codable, Equatable, Sendable {
    case warmUp, run, walk, coolDown
}

public struct SessionReference: Codable, Equatable, Sendable {
    public let programID: String
    public let programVersion: Int
    public let sessionID: String

    public init(programID: String, programVersion: Int, sessionID: String) {
        self.programID = programID
        self.programVersion = programVersion
        self.sessionID = sessionID
    }
}

public enum ProgramError: Error, Equatable {
    case invalidProgram
    case invalidSession
    case duplicateSession
}
