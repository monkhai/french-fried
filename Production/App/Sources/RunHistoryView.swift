import SwiftUI
import MapKit
import Supabase

struct SavedRun: Decodable, Identifiable {
    let id: UUID
    let startedAt: Date
    let activeSeconds: Int
    let distanceMeters: Double
    let programID: String
    let sessionID: String
    let sessionCompleted: Bool

    enum CodingKeys: String, CodingKey {
        case id, startedAt = "started_at", activeSeconds = "active_seconds"
        case distanceMeters = "distance_meters", programID = "program_id"
        case sessionID = "session_id", sessionCompleted = "session_completed"
    }

    var title: String { programID == "illustrative-test" ? "Tracking test" : "Your run" }
    var distance: String { String(format: "%.2f km", distanceMeters / 1_000) }
    var duration: String {
        let hours = activeSeconds / 3_600
        let minutes = (activeSeconds % 3_600) / 60
        let seconds = activeSeconds % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
    var pace: String {
        guard distanceMeters >= 100, activeSeconds > 0 else { return "—" }
        let seconds = Int((Double(activeSeconds) / (distanceMeters / 1_000)).rounded())
        return String(format: "%d:%02d /km", seconds / 60, seconds % 60)
    }
}

struct RunHistoryView: View {
    @Environment(AppSession.self) private var session
    @State private var runs: [SavedRun] = []
    @State private var loading = false
    @State private var hasMore = false
    @State private var nextOffset = 0
    @State private var error: String?
    private let pageSize = 30

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    Text("Every step counts.").font(.title2.bold())
                    Text("Your runs, saved for you. Routes stay private.")
                        .foregroundStyle(.secondary)
                    if runs.isEmpty && loading {
                        ProgressView("Loading your runs…").frame(maxWidth: .infinity).padding(40)
                    } else if runs.isEmpty && error == nil {
                        ContentUnavailableView("Your story starts here", systemImage: "figure.run",
                            description: Text("Finish and save a run from the Runs tab. It will appear here with your time, distance and route."))
                    }
                    ForEach(runs) { run in
                        NavigationLink {
                            SavedRunDetailView(run: run)
                        } label: {
                            runCard(run)
                        }.buttonStyle(.plain)
                    }
                    if let error {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(error, systemImage: "wifi.exclamationmark")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Button("Try again") { Task { await load(reset: runs.isEmpty) } }
                                .buttonStyle(.bordered)
                        }.padding()
                    }
                    if hasMore {
                        Button { Task { await load(reset: false) } } label: {
                            HStack { Spacer(); Text(loading ? "Loading…" : "Load earlier runs"); Spacer() }
                        }.buttonStyle(.bordered).disabled(loading)
                    }
                }.padding(20)
            }
            .background(Color(red: 0.98, green: 0.96, blue: 0.92).ignoresSafeArea())
            .navigationTitle("History")
            .refreshable { await load(reset: true) }
            .task { await load(reset: true) }
        }
    }

    private func runCard(_ run: SavedRun) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "figure.run").foregroundStyle(.orange)
                Text(run.title).font(.headline)
                Spacer()
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
            }
            Text(run.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 24) {
                metric("Distance", run.distance)
                metric("Active time", run.duration)
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 24))
            .accessibilityElement(children: .combine)
    }

    @MainActor private func load(reset: Bool) async {
        guard !loading else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            let owner = try await session.client.auth.session.user.id
            let offset = reset ? 0 : nextOffset
            let page: [SavedRun] = try await session.client.from("runs")
                .select("id,started_at,active_seconds,distance_meters,program_id,session_id,session_completed")
                .eq("owner_id", value: owner)
                .order("started_at", ascending: false).order("id", ascending: false)
                .range(from: offset, to: offset + pageSize - 1).execute().value
            try Task.checkCancellation()
            if reset { runs = page }
            else {
                let existing = Set(runs.map(\.id))
                runs.append(contentsOf: page.filter { !existing.contains($0.id) })
            }
            nextOffset = offset + page.count
            hasMore = page.count == pageSize
        } catch is CancellationError {
        } catch {
            self.error = "Couldn't load your runs. Check your connection and try again."
        }
    }
}

private struct SavedRoute: Decodable {
    struct Point: Decodable {
        let latitude: Double
        let longitude: Double
        let segment: Int
        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }
    let points: [Point]
}

private struct SavedRunDetailView: View {
    let run: SavedRun
    @Environment(AppSession.self) private var session
    @State private var route: SavedRoute?
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(run.startedAt.formatted(date: .complete, time: .shortened))
                    .font(.subheadline).foregroundStyle(.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 28) { metrics }
                    VStack(alignment: .leading, spacing: 16) { metrics }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 24))
                Label("Your private route", systemImage: "lock.fill").font(.headline)
                routeContent
                Text("Your group can see run summaries, never your route. Active time and pace exclude pauses.")
                    .font(.footnote).foregroundStyle(.secondary)
                if run.programID == "illustrative-test" {
                    Text("This was a tracking test with illustrative intervals. It doesn't advance your training program.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.padding(20)
        }
        .background(Color(red: 0.98, green: 0.96, blue: 0.92).ignoresSafeArea())
        .navigationTitle(run.title).navigationBarTitleDisplayMode(.inline)
        .task { await loadRoute() }
    }

    @ViewBuilder private var metrics: some View {
        metric("Distance", run.distance)
        metric("Active time", run.duration)
        metric("Avg. pace", run.pace)
    }

    @ViewBuilder private var routeContent: some View {
        if loading {
            ProgressView("Loading route…").frame(maxWidth: .infinity).frame(height: 220)
        } else if let error {
            VStack(spacing: 12) {
                Text(error).foregroundStyle(.secondary)
                Button("Retry route") { Task { await loadRoute() } }.buttonStyle(.bordered)
            }.frame(maxWidth: .infinity).padding(24)
        } else if let route, !route.points.isEmpty {
            Map {
                ForEach(Array(Set(route.points.map(\.segment))).sorted(), id: \.self) { segment in
                    MapPolyline(coordinates: route.points.filter { $0.segment == segment }.map(\.coordinate))
                        .stroke(.orange, lineWidth: 5)
                }
                if let first = route.points.first {
                    Marker("Start", systemImage: "play.fill", coordinate: first.coordinate).tint(.green)
                }
                if route.points.count > 1, let last = route.points.last {
                    Marker("Finish", systemImage: "flag.fill", coordinate: last.coordinate).tint(.orange)
                }
            }.mapStyle(.standard(elevation: .flat)).frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .accessibilityLabel("Private map of your saved run, with start and finish markers")
        } else {
            ContentUnavailableView("No route recorded", systemImage: "map",
                description: Text("Your time is saved. A route appears when GPS points were recorded during the run."))
        }
    }

    @MainActor private func loadRoute() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let owner = try await session.client.auth.session.user.id
            let rows: [SavedRoute] = try await session.client.from("run_routes").select("points")
                .eq("owner_id", value: owner).eq("run_id", value: run.id).limit(1).execute().value
            try Task.checkCancellation()
            route = rows.first
        } catch is CancellationError {
        } catch {
            self.error = "Couldn't load this route. Your run is still saved."
        }
    }
}

private func metric(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
        Text(value).font(.title3.bold()).monospacedDigit()
        Text(title).font(.caption).foregroundStyle(.secondary)
    }
}
