import Foundation
import RunTracking

struct RunRecovery: Codable, Identifiable {
    let id: UUID
    let owner: UUID
    let sessionID: String?
    let checkpoint: RunCheckpoint?
    let finishedRun: RecordedRun?
}

/// One atomic local checkpoint, scoped to the signed-in account.
enum RunRecoveryStore {
    private static func file(owner: UUID) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("unfinished-run-\(owner.uuidString).json")
    }

    static func load(owner: UUID) -> RunRecovery? {
        guard let data = try? Data(contentsOf: file(owner: owner)),
              let recovery = try? JSONDecoder().decode(RunRecovery.self, from: data),
              recovery.owner == owner else { return nil }
        return recovery
    }

    static func save(_ recovery: RunRecovery) throws {
        let file = file(owner: recovery.owner)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(recovery)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func clear(id: UUID, owner: UUID) {
        let file = file(owner: owner)
        guard let data = try? Data(contentsOf: file),
              let recovery = try? JSONDecoder().decode(RunRecovery.self, from: data), recovery.id == id else { return }
        try? FileManager.default.removeItem(at: file)
    }
}
