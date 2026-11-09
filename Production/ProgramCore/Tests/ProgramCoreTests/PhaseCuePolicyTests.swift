import XCTest
@testable import ProgramCore

final class PhaseCuePolicyTests: XCTestCase {
    private func engine() throws -> IntervalEngine {
        try IntervalEngine(session: TrainingSession(id: "cue-test", week: 1, number: 1, phases: [
            .init(kind: .warmUp, durationSeconds: 5), .init(kind: .run, durationSeconds: 5),
            .init(kind: .walk, durationSeconds: 5), .init(kind: .coolDown, durationSeconds: 5)
        ]))
    }

    func testNoCuesBeforeStartOrDuplicatesAfterPauseResume() throws {
        var engine = try engine()
        var policy = PhaseCuePolicy()
        XCTAssertNil(policy.next(engine: engine, isRunning: false))
        engine.resume(at: 0)
        XCTAssertNotNil(policy.next(engine: engine, isRunning: true))
        XCTAssertNil(policy.next(engine: engine, isRunning: true))
        engine.pause(at: 2)
        XCTAssertNil(policy.next(engine: engine, isRunning: false))
        engine.resume(at: 20)
        XCTAssertNil(policy.next(engine: engine, isRunning: true))
    }

    func testLatestPhaseAndCompletionAreAnnouncedOnlyOnce() throws {
        var engine = try engine()
        var policy = PhaseCuePolicy()
        engine.resume(at: 0)
        engine.update(at: 11)
        XCTAssertEqual(policy.next(engine: engine, isRunning: true), "Time to walk.")
        XCTAssertNil(policy.next(engine: engine, isRunning: true))
        engine.update(at: 16)
        XCTAssertEqual(policy.next(engine: engine, isRunning: true), "Time for your cool-down walk.")
        engine.update(at: 20)
        XCTAssertNotNil(policy.next(engine: engine, isRunning: true))
        XCTAssertNil(policy.next(engine: engine, isRunning: true))
    }

    func testDelayedForegroundUpdateOnlyAnnouncesCurrentPhase() throws {
        var engine = try engine()
        var policy = PhaseCuePolicy()
        engine.resume(at: 0)
        engine.update(at: 11)
        XCTAssertEqual(policy.next(engine: engine, isRunning: true), "Time to walk.")
        XCTAssertNil(policy.next(engine: engine, isRunning: true))
    }
}
