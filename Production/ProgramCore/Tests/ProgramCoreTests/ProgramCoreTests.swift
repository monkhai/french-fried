import XCTest
@testable import ProgramCore

final class ProgramCoreTests: XCTestCase {
    private let session = TrainingSession(id: "example", week: 1, number: 1, phases: [
        SessionPhase(kind: .warmUp, durationSeconds: 5),
        SessionPhase(kind: .run, durationSeconds: 10),
        SessionPhase(kind: .walk, durationSeconds: 5)
    ])

    func testRecoveredElapsedRestoresIntervalAndDoesNotCountTimeAway() throws {
        var engine = try IntervalEngine(session: session)
        engine.resume(at: 0)
        engine.update(at: 7)
        engine.pause(at: 7)
        XCTAssertEqual(engine.currentPhase?.kind, .run)
        XCTAssertEqual(engine.remainingInPhase, 8)
        engine.resume(at: 7)
        engine.update(at: 9)
        XCTAssertEqual(engine.remainingInPhase, 6)
    }

    func testDelayedUpdateCrossesMultiplePhasesAndClampsAtCompletion() throws {
        var engine = try IntervalEngine(session: session)
        engine.resume(at: 100)
        engine.update(at: 117)
        XCTAssertEqual(engine.phaseIndex, 2)
        XCTAssertEqual(engine.currentPhase?.kind, .walk)
        XCTAssertEqual(engine.remainingInPhase, 3)
        XCTAssertEqual(engine.activeElapsed, 17)
        engine.update(at: 130)
        XCTAssertEqual(engine.state, .completed)
        XCTAssertNil(engine.currentPhase)
        XCTAssertEqual(engine.activeElapsed, 20)
    }

    func testPauseAndResumeExcludePausedTime() throws {
        var engine = try IntervalEngine(session: session)
        engine.resume(at: 0)
        engine.pause(at: 7)
        XCTAssertEqual(engine.currentPhase?.kind, .run)
        XCTAssertEqual(engine.remainingInPhase, 8)
        engine.update(at: 100)
        engine.resume(at: 100)
        engine.update(at: 103)
        XCTAssertEqual(engine.remainingInPhase, 5)
        XCTAssertEqual(engine.activeElapsed, 10)
    }

    func testExactBoundaryTransitionsAndInvalidTimeIsIgnored() throws {
        var engine = try IntervalEngine(session: session)
        engine.resume(at: 10)
        engine.update(at: 15)
        XCTAssertEqual(engine.currentPhase?.kind, .run)
        XCTAssertEqual(engine.remainingInPhase, 10)
        engine.update(at: 12)
        engine.update(at: .nan)
        engine.update(at: 16)
        XCTAssertEqual(engine.activeElapsed, 6)
    }

    func testRejectsInvalidAndDuplicateSessions() throws {
        let invalid = TrainingSession(id: "", week: 1, number: 1, phases: [])
        XCTAssertThrowsError(try IntervalEngine(session: invalid))
        let program = TrainingProgram(id: "test", version: 1, sessions: [session, session])
        XCTAssertThrowsError(try program.validate()) { XCTAssertEqual($0 as? ProgramError, .duplicateSession) }
    }

    func testInvalidPauseDoesNotStopClock() throws {
        var engine = try IntervalEngine(session: session)
        engine.resume(at: 10)
        engine.update(at: 12)
        engine.pause(at: 11)
        engine.pause(at: .nan)
        XCTAssertEqual(engine.state, .running)
        engine.pause(at: 14)
        XCTAssertEqual(engine.state, .paused)
        XCTAssertEqual(engine.activeElapsed, 4)
    }
}
