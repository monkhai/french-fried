# RunTracking

Native Core Location run recording for iOS 26+. The production app owns one `RunTracker` for an active run and reads its observable `state`, `elapsedSeconds`, `distanceMeters`, `locations`, and `issue`. Call `start()`, `pause()`, `resume()`, and `finish()`; `finish()` returns a `RecordedRun` to persist. A tracker records one run; create a new tracker for the next one.

For an idle map preview, `prepareLocation()` requests a single fix only if permission already exists; it never prompts or starts the run clock. `latestLocation` is separate from recorded route points and can have lower accuracy. Use `preciseLocationEnabled` to offer a Settings action when approximate access prevents accurate route recording. The clock continues updating during map gestures. Background-delivered samples are accepted by capture time within the active segment, even when delivery is delayed.

The app must supply `NSLocationWhenInUseUsageDescription` and include `location` in `UIBackgroundModes`. The tracker only enables Core Location background updates when that mode exists in the host's Info.plist. Start location updates while the app is in the foreground. The view should surface `issue` and permission-denied state. Route points include a segment number so pause/resume does not draw or measure a straight line across the gap.

This package does not save runs, sync them, play interval cues, restart after process termination, or configure the host app's capabilities. Time is based on recorded timestamps, so it catches up after backgrounding while the process remains alive; the app must retain the tracker during a run. Test actual background and location behavior on device as well as Simulator. Raw GPS distance is an estimate, subject to location accuracy and jitter.
