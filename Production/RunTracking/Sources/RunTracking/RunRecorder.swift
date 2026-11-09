import Foundation
import CoreLocation

public struct RunLocation: Codable, Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let recordedAt: Date
    public let horizontalAccuracy: Double
    // A new segment begins on resume; do not connect it to the previous segment.
    public let segment: Int
}

public struct RecordedRun: Codable, Equatable, Sendable {
    public let startedAt: Date
    public let endedAt: Date
    public let activeSeconds: TimeInterval
    public let distanceMeters: Double
    public let locations: [RunLocation]
}

public enum RunRecorderState: Equatable, Sendable {
    case idle, running, paused, finished
}

/// A durable checkpoint. Restoring always pauses the run at the last recorded instant.
public struct RunCheckpoint: Codable, Equatable, Sendable {
    public let startedAt: Date
    public let activeSeconds: TimeInterval
    public let distanceMeters: Double
    public let locations: [RunLocation]
    public let segment: Int
}

/// The in-memory record of one run. Timestamps are injected for deterministic tests.
public struct RunRecorder {
    public private(set) var state: RunRecorderState = .idle
    public private(set) var startedAt: Date?
    public private(set) var distanceMeters: Double = 0
    public private(set) var locations: [RunLocation] = []
    private var activeSeconds: TimeInterval = 0
    private var resumedAt: Date?
    private var lastLocation: CLLocation?
    private var segment = 0

    public init() {}

    public func checkpoint(at date: Date = Date()) -> RunCheckpoint? {
        guard (state == .running || state == .paused), let startedAt else { return nil }
        return RunCheckpoint(startedAt: startedAt, activeSeconds: elapsed(at: date),
                             distanceMeters: distanceMeters, locations: locations, segment: segment)
    }

    public init(recovering checkpoint: RunCheckpoint) {
        self.startedAt = checkpoint.startedAt
        self.activeSeconds = checkpoint.activeSeconds
        self.distanceMeters = checkpoint.distanceMeters
        self.locations = checkpoint.locations
        self.segment = checkpoint.segment
        self.state = .paused
    }

    public mutating func start(at date: Date = Date()) {
        guard state == .idle else { return }
        startedAt = date
        resumedAt = date
        state = .running
    }

    public func elapsed(at date: Date = Date()) -> TimeInterval {
        activeSeconds + (state == .running ? max(0, date.timeIntervalSince(resumedAt ?? date)) : 0)
    }

    public mutating func pause(at date: Date = Date()) {
        guard state == .running else { return }
        activeSeconds = elapsed(at: date)
        resumedAt = nil
        lastLocation = nil
        state = .paused
    }

    public mutating func resume(at date: Date = Date()) {
        guard state == .paused else { return }
        segment += 1
        resumedAt = date
        state = .running
    }

    /// Adds a GPS reading only if it was captured during the current running segment.
    @discardableResult
    public mutating func record(_ location: CLLocation, receivedAt date: Date = Date()) -> Bool {
        guard state == .running, let resumedAt,
              // Compare intervals directly: Date >= is newly back-deployed by
              // the 27.2 SDK and can call a missing symbol on early 27.2 betas.
              location.timestamp.timeIntervalSince(resumedAt) >= 0,
              location.timestamp.timeIntervalSince(date) <= 1,
              location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 50,
              CLLocationCoordinate2DIsValid(location.coordinate) else { return false }
        // Background delivery may be delayed. Capture time within this active
        // segment, rather than callback age, determines whether a point belongs.
        if let previous = lastLocation {
            guard location.timestamp.timeIntervalSince(previous.timestamp) > 0 else { return false }
            distanceMeters += location.distance(from: previous)
        }
        lastLocation = location
        locations.append(RunLocation(latitude: location.coordinate.latitude,
                                     longitude: location.coordinate.longitude,
                                     recordedAt: location.timestamp,
                                     horizontalAccuracy: location.horizontalAccuracy,
                                     segment: segment))
        return true
    }

    public mutating func finish(at date: Date = Date()) -> RecordedRun? {
        guard state == .running || state == .paused, let startedAt else { return nil }
        let duration = elapsed(at: date)
        activeSeconds = duration
        state = .finished
        resumedAt = nil
        lastLocation = nil
        return RecordedRun(startedAt: startedAt, endedAt: date, activeSeconds: duration,
                           distanceMeters: distanceMeters, locations: locations)
    }
}
