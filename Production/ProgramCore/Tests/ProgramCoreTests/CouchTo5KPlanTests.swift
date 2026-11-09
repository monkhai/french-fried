import XCTest
@testable import ProgramCore

final class CouchTo5KPlanTests: XCTestCase {
    func testPublishedEditionHasExactly27UniqueOrderedSessions() throws {
        let program = CouchTo5KPlan.program
        try program.validate()
        XCTAssertEqual(program.id, "couch-to-5k")
        XCTAssertEqual(program.version, 1)
        XCTAssertEqual(program.sessions.count, 27)
        for (index, session) in program.sessions.enumerated() {
            XCTAssertEqual(session.week, index / 3 + 1)
            XCTAssertEqual(session.number, index % 3 + 1)
            XCTAssertEqual(session.id, "w\(index / 3 + 1)-r\(index % 3 + 1)")
            XCTAssertEqual(session.phases.first, SessionPhase(kind: .warmUp, durationSeconds: 300))
            XCTAssertEqual(session.phases.last, SessionPhase(kind: .coolDown, durationSeconds: 300))
        }
    }

    func testSessionTotalsMatchSourceIncludingFinalRunsAndCooldown() {
        let expectedTotals = [
            1710, 1710, 1710, 1740, 1740, 1740, 1500, 1500, 1500,
            1890, 1890, 1890, 1860, 1860, 1800, 2040, 1980, 2100,
            2100, 2100, 2100, 2280, 2280, 2280, 2400, 2400, 2400
        ]
        XCTAssertEqual(CouchTo5KPlan.program.sessions.map(\.totalDurationSeconds), expectedTotals)
        let expectedRunning = [
            480, 480, 480, 540, 540, 540, 540, 540, 540,
            960, 960, 960, 900, 960, 1200, 1080, 1200, 1500,
            1500, 1500, 1500, 1680, 1680, 1680, 1800, 1800, 1800
        ]
        XCTAssertEqual(CouchTo5KPlan.program.sessions.map(\.runningDurationSeconds), expectedRunning)
    }

    func testDistinctMiddleWeeksHaveCorrectOrderedPhases() {
        let sessions = CouchTo5KPlan.program.sessions
        let expected = [
            [300, 300, 180, 300, 180, 300, 300],
            [300, 480, 300, 480, 300],
            [300, 1200, 300],
            [300, 300, 180, 480, 180, 300, 300],
            [300, 600, 180, 600, 300],
            [300, 1500, 300]
        ]
        XCTAssertEqual(Array(sessions[12...17]).map { $0.phases.map(\.durationSeconds) }, expected)
        for session in sessions {
            for (index, phase) in session.phases.dropFirst().dropLast().enumerated() {
                XCTAssertEqual(phase.kind, index.isMultiple(of: 2) ? .run : .walk)
            }
        }
    }

    func testAllSessionsCompleteOnlyAfterEntireCooldown() throws {
        for session in CouchTo5KPlan.program.sessions {
            var engine = try IntervalEngine(session: session)
            engine.resume(at: 0)
            engine.update(at: Double(session.totalDurationSeconds - 1))
            XCTAssertEqual(engine.state, .running)
            XCTAssertEqual(engine.currentPhase?.kind, .coolDown)
            engine.update(at: Double(session.totalDurationSeconds))
            XCTAssertEqual(engine.state, .completed)
            XCTAssertEqual(engine.activeElapsed, Double(session.totalDurationSeconds))
        }
    }
}
