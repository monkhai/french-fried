import XCTest
import CoreLocation
@testable import RunTracking

final class RunRecorderTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func testRecoveryPreservesRunAndExcludesTimeAwayAndRouteGap() throws {
        var recorder = RunRecorder()
        recorder.start(at: start)
        XCTAssertTrue(recorder.record(point(32, 1), receivedAt: start.addingTimeInterval(1)))
        XCTAssertTrue(recorder.record(point(32.0001, 2), receivedAt: start.addingTimeInterval(2)))
        let checkpoint = try XCTUnwrap(recorder.checkpoint(at: start.addingTimeInterval(10)))
        let encoded = try JSONEncoder().encode(checkpoint)
        let decoded = try JSONDecoder().decode(RunCheckpoint.self, from: encoded)
        var recovered = RunRecorder(recovering: decoded)
        XCTAssertEqual(recovered.state, .paused)
        XCTAssertEqual(recovered.elapsed(at: start.addingTimeInterval(100)), 10)
        recovered.resume(at: start.addingTimeInterval(100))
        XCTAssertTrue(recovered.record(point(33, 101), receivedAt: start.addingTimeInterval(101)))
        XCTAssertEqual(recovered.distanceMeters, checkpoint.distanceMeters, accuracy: 0.001)
        let result = try XCTUnwrap(recovered.finish(at: start.addingTimeInterval(105)))
        XCTAssertEqual(result.activeSeconds, 15)
        XCTAssertEqual(result.locations.map(\.segment), [0, 0, 1])
        XCTAssertEqual(result.startedAt, start)
    }

    private func point(_ latitude: Double, _ time: TimeInterval, accuracy: Double = 5) -> CLLocation {
        CLLocation(coordinate: .init(latitude: latitude, longitude: 34.77), altitude: 0,
                   horizontalAccuracy: accuracy, verticalAccuracy: 5,
                   timestamp: start.addingTimeInterval(time))
    }

    func testPausedTimeAndRouteGapAreExcluded() throws {
        var recorder = RunRecorder()
        recorder.start(at: start)
        XCTAssertTrue(recorder.record(point(32.0, 1), receivedAt: start.addingTimeInterval(1)))
        XCTAssertTrue(recorder.record(point(32.0001, 2), receivedAt: start.addingTimeInterval(2)))
        let distanceBeforePause = recorder.distanceMeters
        recorder.pause(at: start.addingTimeInterval(10))
        XCTAssertFalse(recorder.record(point(33.0, 12), receivedAt: start.addingTimeInterval(12)))
        recorder.resume(at: start.addingTimeInterval(30))
        XCTAssertTrue(recorder.record(point(33.0, 31), receivedAt: start.addingTimeInterval(31)))
        XCTAssertEqual(recorder.distanceMeters, distanceBeforePause, accuracy: 0.01)
        let run = try XCTUnwrap(recorder.finish(at: start.addingTimeInterval(35)))
        XCTAssertEqual(run.activeSeconds, 15, accuracy: 0.001)
        XCTAssertEqual(run.locations.map(\.segment), [0, 0, 1])
        XCTAssertEqual(recorder.state, .finished)
        XCTAssertNil(recorder.finish(at: start.addingTimeInterval(40)))
    }

    func testRejectsStaleInaccurateAndOutOfOrderLocations() {
        var recorder = RunRecorder()
        recorder.start(at: start)
        XCTAssertFalse(recorder.record(point(32, 1, accuracy: 51), receivedAt: start.addingTimeInterval(1)))
        XCTAssertFalse(recorder.record(point(32, -1), receivedAt: start.addingTimeInterval(17)))
        XCTAssertTrue(recorder.record(point(32, 2), receivedAt: start.addingTimeInterval(2)))
        XCTAssertFalse(recorder.record(point(32, 1), receivedAt: start.addingTimeInterval(2)))
        XCTAssertEqual(recorder.locations.count, 1)
    }

    func testFinishWhilePausedDoesNotAddPausedTime() throws {
        var recorder = RunRecorder()
        recorder.start(at: start)
        recorder.pause(at: start.addingTimeInterval(10))
        let run = try XCTUnwrap(recorder.finish(at: start.addingTimeInterval(100)))
        XCTAssertEqual(run.activeSeconds, 10)
    }

    func testFinishedElapsedRemainsFrozenAfterFinalRunningSegment() throws {
        var recorder = RunRecorder()
        recorder.start(at: start)
        recorder.pause(at: start.addingTimeInterval(10))
        recorder.resume(at: start.addingTimeInterval(40))
        let run = try XCTUnwrap(recorder.finish(at: start.addingTimeInterval(55)))
        XCTAssertEqual(run.activeSeconds, 25)
        XCTAssertEqual(recorder.elapsed(at: start.addingTimeInterval(100)), 25)
        recorder.resume(at: start.addingTimeInterval(101))
        recorder.start(at: start.addingTimeInterval(102))
        XCTAssertEqual(recorder.state, .finished)
        XCTAssertFalse(recorder.record(point(32, 103), receivedAt: start.addingTimeInterval(103)))
        XCTAssertEqual(recorder.elapsed(at: start.addingTimeInterval(104)), 25)
    }

    func testDelayedPreResumeAndFutureLocationsCannotExtendRoute() {
        var recorder = RunRecorder()
        recorder.start(at: start)
        XCTAssertTrue(recorder.record(point(32, 1), receivedAt: start.addingTimeInterval(1)))
        recorder.pause(at: start.addingTimeInterval(3))
        recorder.resume(at: start.addingTimeInterval(5))
        XCTAssertFalse(recorder.record(point(33, 4), receivedAt: start.addingTimeInterval(6)))
        XCTAssertFalse(recorder.record(point(33, 10), receivedAt: start.addingTimeInterval(6)))
        XCTAssertTrue(recorder.record(point(33, 6), receivedAt: start.addingTimeInterval(6)))
        XCTAssertEqual(recorder.distanceMeters, 0)
        XCTAssertEqual(recorder.locations.map(\.segment), [0, 1])
    }

    func testTimestampBoundariesAcrossRepeatedPauseResume() throws {
        var recorder = RunRecorder()
        recorder.start(at: start)
        XCTAssertTrue(recorder.record(point(32, 0), receivedAt: start))
        XCTAssertFalse(recorder.record(point(32.001, 0), receivedAt: start))
        for cycle in 1...10 {
            let pauseTime = Double(cycle * 10 - 5)
            let resumeTime = Double(cycle * 10)
            recorder.pause(at: start.addingTimeInterval(pauseTime))
            recorder.pause(at: start.addingTimeInterval(pauseTime + 1))
            XCTAssertFalse(recorder.record(point(33, pauseTime), receivedAt: start.addingTimeInterval(pauseTime)))
            recorder.resume(at: start.addingTimeInterval(resumeTime))
            recorder.resume(at: start.addingTimeInterval(resumeTime + 1))
            XCTAssertFalse(recorder.record(point(33, resumeTime - 0.001), receivedAt: start.addingTimeInterval(resumeTime)))
            XCTAssertTrue(recorder.record(point(33, resumeTime), receivedAt: start.addingTimeInterval(resumeTime)))
            XCTAssertFalse(recorder.record(point(33.001, resumeTime), receivedAt: start.addingTimeInterval(resumeTime)))
        }
        let run = try XCTUnwrap(recorder.finish(at: start.addingTimeInterval(105)))
        XCTAssertEqual(run.activeSeconds, 55)
        XCTAssertEqual(run.distanceMeters, 0)
        XCTAssertEqual(run.locations.count, 11)
        XCTAssertEqual(run.locations.map(\.segment), Array(0...10))
    }

    func testDelayedBackgroundBatchKeepsPointsCapturedDuringActiveSegment() throws {
        var recorder = RunRecorder()
        recorder.start(at: start)
        let deliveredAt = start.addingTimeInterval(120)
        XCTAssertTrue(recorder.record(point(32, 10), receivedAt: deliveredAt))
        XCTAssertTrue(recorder.record(point(32.0001, 30), receivedAt: deliveredAt))
        XCTAssertTrue(recorder.record(point(32.0002, 90), receivedAt: deliveredAt))
        XCTAssertFalse(recorder.record(point(32, 60), receivedAt: deliveredAt))
        let run = try XCTUnwrap(recorder.finish(at: deliveredAt))
        XCTAssertEqual(run.locations.count, 3)
        XCTAssertGreaterThan(run.distanceMeters, 20)
        XCTAssertEqual(run.activeSeconds, 120)
    }
}
