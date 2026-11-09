import SwiftUI
import Supabase

private struct Membership: Decodable { let group_id: UUID }
private struct Crew: Decodable { let id: UUID; let name: String }
private struct InvitePreview: Decodable { let group_id: UUID; let group_name: String }
private struct MemberProgress: Decodable, Identifiable {
    let member_id: UUID
    let display_name: String
    let current_week: Int
    let weekly_runs: Int
    var id: UUID { member_id }
}
private struct CrewActivity: Decodable, Identifiable {
    let activity_id: UUID
    let activity_kind: String
    let occurred_at: String
    let display_name: String
    let distance_meters: Double?
    let active_seconds: Int?
    let milestone_week: Int?
    var id: UUID { activity_id }
}
private struct GroupParam: Encodable { let p_group_id: UUID }
private struct NameParam: Encodable { let p_name: String }
private struct TokenParam: Encodable { let p_token: UUID }

struct GroupView: View {
    @Environment(AppSession.self) private var session
    @State private var group: Crew?
    @State private var members: [MemberProgress] = []
    @State private var activity: [CrewActivity] = []
    @State private var invite: UUID?
    @State private var groupName = ""
    @State private var inviteText = ""
    @State private var preview: InvitePreview?
    @State private var busy = false
    @State private var hasLoaded = false
    @State private var error: String?
    @State private var confirmLeave = false

    var body: some View {
        NavigationStack {
            Form {
                if !hasLoaded && busy {
                    ProgressView("Loading your crew…")
                } else if let group {
                    Section(group.name) {
                        let count = members.reduce(0) { $0 + $1.weekly_runs }
                        Text("This week: \(count) / \(members.count * 3) runs")
                            .font(.headline)
                        Text("Each member contributes up to three saved runs. Resets Monday UTC.")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(members) { member in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(member.display_name).font(.headline)
                                    Text("Week \(member.current_week)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(member.weekly_runs) / 3 runs").font(.subheadline)
                            }
                        }
                    }
                    Section("Invite friends") {
                        if let invite {
                            ShareLink(item: invite.uuidString, subject: Text("Join my French Fried crew"), message: Text("Paste this code in French Fried to join my crew.")) {
                                Label("Share invite code", systemImage: "square.and.arrow.up")
                            }
                            Text("Friends can paste this code in the Group tab.").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Button("Load invite code") { Task { await loadInvite(group.id) } }.disabled(busy)
                        }
                    }
                    Section("Activity") {
                        if activity.isEmpty { Text("No activity yet.").foregroundStyle(.secondary) }
                        ForEach(activity) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(activityTitle(item)).font(.subheadline.weight(.medium))
                                if let meters = item.distance_meters, let seconds = item.active_seconds {
                                    Text(String(format: "%.2f km · %d:%02d", meters / 1000, seconds / 60, seconds % 60))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Text(dateLabel(item.occurred_at)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section {
                        Label("Routes stay private", systemImage: "lock.fill").font(.subheadline)
                        Button("Leave group", role: .destructive) { confirmLeave = true }.disabled(busy)
                    }
                } else if hasLoaded {
                    Section {
                        Text("Better together.").font(.title2.bold())
                        Text("Share progress and run summaries with a small group. Your routes stay private.")
                            .foregroundStyle(.secondary)
                    }
                    Section("Create a group") {
                        TextField("Group name", text: $groupName).textInputAutocapitalization(.words)
                        Button("Create group") { Task { await createGroup() } }
                            .disabled(busy || groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Section("Join a group") {
                        TextField("Invite code", text: $inviteText).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .onChange(of: inviteText) { _, _ in preview = nil }
                        if let preview {
                            Text("Join \(preview.group_name)?")
                            Button("Join group") { Task { await joinGroup() } }.disabled(busy)
                        } else {
                            Button("Find group") { Task { await previewInvite() } }.disabled(busy || inviteText.isEmpty)
                        }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.98, green: 0.96, blue: 0.92))
            .navigationTitle("The crew")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Refresh") { Task { await refresh() } }.disabled(busy) } }
            .task { if !hasLoaded { await refresh() } }
            .confirmationDialog("Leave this group?", isPresented: $confirmLeave, titleVisibility: .visible) {
                Button("Leave group", role: .destructive) { Task { await leaveGroup() } }
                Button("Cancel", role: .cancel) { }
            } message: { Text("Your runs and progress stay with you.") }
        }
    }

    private func refresh() async {
        busy = true; error = nil
        defer { busy = false }
        do {
            let userID = try await session.client.auth.session.user.id
            let memberships: [Membership] = try await session.client.from("group_members").select("group_id").eq("user_id", value: userID).execute().value
            guard let membership = memberships.first else {
                group = nil; members = []; activity = []; invite = nil; hasLoaded = true
                return
            }
            let groups: [Crew] = try await session.client.from("running_groups").select("id,name").eq("id", value: membership.group_id).execute().value
            guard let current = groups.first else { throw GroupError.inconsistentMembership }
            let params = GroupParam(p_group_id: current.id)
            let newMembers: [MemberProgress] = try await session.client.rpc("list_group_progress", params: params).execute().value
            let newActivity: [CrewActivity] = try await session.client.rpc("list_group_activity", params: params).execute().value
            group = current; members = newMembers; activity = newActivity; invite = nil; hasLoaded = true
        } catch {
            self.error = "Couldn't load your group. Check your connection and try again."
        }
    }

    private func createGroup() async {
        busy = true; error = nil
        do {
            let _: UUID = try await session.client.rpc("create_group", params: NameParam(p_name: groupName.trimmingCharacters(in: .whitespacesAndNewlines))).execute().value
            groupName = ""; busy = false; await refresh()
        } catch { busy = false; self.error = "Couldn't create the group. Check the name and try again." }
    }
    private func previewInvite() async {
        guard let token = UUID(uuidString: inviteText.trimmingCharacters(in: .whitespacesAndNewlines)) else { error = "Enter a valid invite code."; return }
        busy = true; error = nil
        do {
            let results: [InvitePreview] = try await session.client.rpc("preview_group_invite", params: TokenParam(p_token: token)).execute().value
            preview = results.first
            if preview == nil { error = "This invite is invalid or the group no longer exists." }
        } catch { self.error = "Couldn't check this invite. Please try again." }
        busy = false
    }
    private func joinGroup() async {
        guard let token = UUID(uuidString: inviteText.trimmingCharacters(in: .whitespacesAndNewlines)), preview != nil else { return }
        busy = true; error = nil
        do {
            let _: UUID = try await session.client.rpc("join_group", params: TokenParam(p_token: token)).execute().value
            preview = nil; inviteText = ""; busy = false; await refresh()
        } catch { busy = false; self.error = "Couldn't join. The invite may have changed or you may already belong to a group." }
    }
    private func loadInvite(_ id: UUID) async {
        busy = true; error = nil
        do { invite = try await session.client.rpc("get_group_invite", params: GroupParam(p_group_id: id)).execute().value }
        catch { self.error = "Couldn't load the invite code. Please try again." }
        busy = false
    }
    private func leaveGroup() async {
        guard let group else { return }
        busy = true; error = nil
        do {
            try await session.client.rpc("leave_group", params: GroupParam(p_group_id: group.id)).execute()
            busy = false; await refresh()
        } catch { busy = false; self.error = "Couldn't leave the group. Please try again." }
    }
    private func activityTitle(_ item: CrewActivity) -> String {
        switch item.activity_kind {
        case "run": return "\(item.display_name) saved a run"
        case "week_completed": return "\(item.display_name) completed week \(item.milestone_week ?? 0)"
        case "program_completed": return "\(item.display_name) completed the program"
        default: return "\(item.display_name) reached a milestone"
        }
    }
    private func dateLabel(_ value: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        return date?.formatted(date: .abbreviated, time: .shortened) ?? value
    }
    private enum GroupError: Error { case inconsistentMembership }
}
