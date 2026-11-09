import SwiftUI
import UIKit
import ProgramCore

struct AppTabs: View {
    @Environment(AppSession.self) private var session
    @State private var tab = 0
    @State private var recovery: RunRecovery?

    var body: some View {
        TabView(selection: $tab) {
            HomeView(showRuns: { tab = 1 })
                .tag(0).tabItem { Label("Home", systemImage: "house.fill") }
            ProgramView()
                .tag(1).tabItem { Label("Runs", systemImage: "figure.run") }
            RunHistoryView()
                .tag(2).tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            GroupView()
                .tag(3).tabItem { Label("Group", systemImage: "person.2") }
            AccountSettingsView()
                .tag(4).tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(.orange)
        .onAppear {
            if let owner = session.recoveryOwnerID { recovery = RunRecoveryStore.load(owner: owner) }
        }
        .fullScreenCover(item: $recovery) { draft in
            if let sessionID = draft.sessionID,
               !CouchTo5KPlan.program.sessions.contains(where: { $0.id == sessionID }) {
                ContentUnavailableView("Can't restore this program", systemImage: "exclamationmark.triangle", description: Text("Your unfinished run is still saved on this device."))
            } else {
                let training = draft.sessionID.flatMap { id in CouchTo5KPlan.program.sessions.first { $0.id == id } }
                TrackingView(trainingSession: training, recovery: draft)
            }
        }
    }
}
