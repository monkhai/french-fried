import SwiftUI

struct HomeView: View {
    let showRuns: () -> Void
    @State private var showingRun = false
    private let cream = Color(red: 0.98, green: 0.96, blue: 0.92)
    private let ink = Color(red: 0.20, green: 0.12, blue: 0.08)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Ready when you are.").font(.subheadline).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 16) {
                        Text("YOUR PROGRAM").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
                        Text("One run at a time.").font(.title2.bold())
                        Text("Choose your next session from the nine-week program.").foregroundStyle(.secondary)
                        Button("View program", action: showRuns).font(.headline)
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 24))
                    VStack(alignment: .leading, spacing: 12) {
                        Text("FREE RUN").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
                        Text("Head out without intervals. Track your time, route and distance.").font(.subheadline)
                        Text("Save your run after finishing.").font(.caption).foregroundStyle(.secondary)
                        Button { showingRun = true } label: {
                            Label("Start run", systemImage: "play.fill").font(.headline)
                                .frame(maxWidth: .infinity).padding(.vertical, 16)
                                .background(.orange, in: Capsule()).foregroundStyle(ink)
                        }
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 24))
                }.padding(20)
            }
            .background(cream.ignoresSafeArea())
            .navigationTitle("Today")
            .fullScreenCover(isPresented: $showingRun) { TrackingView() }
        }.tint(.orange)
    }
}
