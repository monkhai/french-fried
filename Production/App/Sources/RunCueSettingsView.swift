import SwiftUI

enum RunCuePreferences {
    static let voiceKey = "runCues.voiceEnabled"
    static let hapticsKey = "runCues.hapticsEnabled"
}

struct RunCueSettingsView: View {
    @AppStorage(RunCuePreferences.voiceKey) private var voiceEnabled = false
    @AppStorage(RunCuePreferences.hapticsKey) private var hapticsEnabled = false

    var body: some View {
        Form {
            Section {
                Toggle("Voice guidance", isOn: $voiceEnabled)
                Toggle("Haptic cues", isOn: $hapticsEnabled)
            } header: { Text("Guided runs") }
            footer: {
                Text("Hear Ms. Harris during your runs, including when your phone is locked. Voice cues include strong language. Haptics work while the app is open. Both are off by default.")
            }
        }.navigationTitle("Run guidance")
    }
}
