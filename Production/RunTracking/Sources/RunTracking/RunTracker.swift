#if os(iOS)
import Foundation
import CoreLocation
import Observation

/// Own for the lifetime of an active run, including while its screen is backgrounded.
@MainActor
@Observable
public final class RunTracker: NSObject, @preconcurrency CLLocationManagerDelegate {
    public private(set) var recorder = RunRecorder()
    public private(set) var elapsedSeconds: TimeInterval = 0
    public private(set) var authorizationStatus: CLAuthorizationStatus
    public private(set) var waitingForPermission = false
    public private(set) var issue: String?
    public private(set) var backgroundLocationEnabled = false
    public private(set) var preciseLocationEnabled = true
    /// Latest usable map fix, including an authorized pre-run preview. Not a route point.
    public private(set) var latestLocation: CLLocation?
    @ObservationIgnored private let locationManager: CLLocationManager
    @ObservationIgnored private var timer: Timer?

    public override init() {
        let manager = CLLocationManager()
        self.locationManager = manager
        self.authorizationStatus = manager.authorizationStatus
        self.preciseLocationEnabled = manager.accuracyAuthorization == .fullAccuracy
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
        #if os(iOS)
        // Apple requires this Info.plist mode before setting the property to true.
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        if modes.contains("location") {
            manager.allowsBackgroundLocationUpdates = true
            backgroundLocationEnabled = true
        }
        #endif
    }

    public var state: RunRecorderState { recorder.state }

    /// Resume is explicit: elapsed time and GPS are not invented while the app was gone.
    public func restore(_ checkpoint: RunCheckpoint) {
        guard recorder.state == .idle else { return }
        recorder = RunRecorder(recovering: checkpoint)
        elapsedSeconds = checkpoint.activeSeconds
        if let last = checkpoint.locations.last {
            latestLocation = CLLocation(coordinate: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude), altitude: 0, horizontalAccuracy: last.horizontalAccuracy, verticalAccuracy: -1, timestamp: last.recordedAt)
        }
    }
    public var locationPermissionDenied: Bool { authorizationStatus == .denied || authorizationStatus == .restricted }
    public var distanceMeters: Double { recorder.distanceMeters }
    public var locations: [RunLocation] { recorder.locations }
    public var averagePaceSecondsPerKilometer: TimeInterval? {
        guard distanceMeters > 0 else { return nil }
        return elapsedSeconds / (distanceMeters / 1_000)
    }

    /// Fetch a map preview only with existing permission; never prompts or starts a run.
    public func prepareLocation() {
        guard recorder.state == .idle else { return }
        let status = locationManager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else { return }
        locationManager.requestLocation()
    }

    /// Requests location when needed; starts after permission is granted.
    public func start() {
        guard recorder.state == .idle, !waitingForPermission else { return }
        issue = nil
        authorizationStatus = locationManager.authorizationStatus
        preciseLocationEnabled = locationManager.accuracyAuthorization == .fullAccuracy
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            beginRecording()
        case .notDetermined:
            guard Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") as? String != nil else {
                issue = "Location permission description is missing from the app configuration."
                return
            }
            waitingForPermission = true
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            issue = "Location access is needed to record a route."
        @unknown default:
            issue = "Location access is unavailable."
        }
    }

    public func pause() {
        guard recorder.state == .running else { return }
        recorder.pause()
        refreshElapsed()
        locationManager.stopUpdatingLocation()
        timer?.invalidate()
        timer = nil
    }

    public func resume() {
        guard recorder.state == .paused else { return }
        guard locationManager.authorizationStatus == .authorizedAlways || locationManager.authorizationStatus == .authorizedWhenInUse else {
            issue = "Location access is needed to resume tracking."
            return
        }
        issue = preciseLocationEnabled ? nil : "Turn on Precise Location in Settings to record your route and distance."
        recorder.resume()
        locationManager.startUpdatingLocation()
        startClock()
    }

    public func finish() -> RecordedRun? {
        guard let run = recorder.finish() else { return nil }
        locationManager.stopUpdatingLocation()
        timer?.invalidate()
        timer = nil
        elapsedSeconds = run.activeSeconds
        return run
    }

    private func beginRecording() {
        waitingForPermission = false
        issue = preciseLocationEnabled ? "Finding GPS. Your timer is running." : "Turn on Precise Location in Settings to record your route and distance."
        recorder.start()
        locationManager.startUpdatingLocation()
        startClock()
    }

    private func refreshElapsed() { elapsedSeconds = recorder.elapsed() }

    private func startClock() {
        timer?.invalidate()
        refreshElapsed()
        let clock = Timer(timeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            Task { @MainActor in self.refreshElapsed() }
        }
        timer = clock
        // Map pan/zoom gestures put the main run loop in tracking mode.
        RunLoop.main.add(clock, forMode: .common)
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        preciseLocationEnabled = manager.accuracyAuthorization == .fullAccuracy
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if waitingForPermission { beginRecording() }
            else if !preciseLocationEnabled {
                issue = "Turn on Precise Location in Settings to record your route and distance."
            } else if recorder.state == .idle || recorder.state == .paused {
                issue = nil
            }
        case .denied, .restricted:
            waitingForPermission = false
            if recorder.state == .running { pause() }
            issue = "Location access is needed to record a route."
        case .notDetermined:
            break
        @unknown default:
            waitingForPermission = false
            issue = "Location access is unavailable."
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        var acceptedLocation = false
        for location in locations {
            if CLLocationCoordinate2DIsValid(location.coordinate),
               location.horizontalAccuracy >= 0,
               abs(location.timestamp.timeIntervalSinceNow) <= 30,
               latestLocation.map({ location.timestamp.timeIntervalSince($0.timestamp) > 0 }) ?? true {
                latestLocation = location
            }
            if recorder.record(location) { acceptedLocation = true }
        }
        if acceptedLocation, preciseLocationEnabled { issue = nil }
        refreshElapsed()
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A temporary location failure should not stop the timer or discard the run.
        if let locationError = error as? CLError, locationError.code == .locationUnknown { return }
        if let locationError = error as? CLError, locationError.code == .denied {
            authorizationStatus = manager.authorizationStatus
            waitingForPermission = false
            if recorder.state == .running { pause() }
            issue = "Location access was interrupted. Check Settings, then resume your run."
            return
        }
        issue = "Location updates are unavailable: \(error.localizedDescription)"
    }
}

#endif
