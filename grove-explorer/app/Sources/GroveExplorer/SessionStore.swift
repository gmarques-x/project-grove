import Foundation
import GroveExplorerCore
import GroveThemesCore

/// The window's session in `$GROVE_STATE/explorer-session.json` (spec §9):
/// read at launch, written a second after the last change and at quit.
@MainActor
final class SessionStore {
    let file: URL
    private var pending: Task<Void, Never>?

    init(file: URL) {
        self.file = file
    }

    /// Beside grove-themes' state file: `$GROVE_STATE`, default `~/.local/state/grove`.
    static func standardFile() -> URL {
        StatePath.url(environment: ProcessInfo.processInfo.environment, home: FileManager.default.homeDirectoryForCurrentUser)
            .deletingLastPathComponent().appendingPathComponent("explorer-session.json")
    }

    /// Nil without a file, and for a damaged one (spec §13: ignored).
    func load() -> Session? { Session.load(from: file) }

    /// Writes what `session` gives a second from now; a call before then starts the second again.
    func saveSoon(_ session: @escaping @MainActor () -> Session?) {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self, let session = session() else { return }
            self.save(session)
        }
    }

    func save(_ session: Session) {
        pending?.cancel()
        pending = nil
        do {
            try session.save(to: file)
        } catch {
            // The window works without it; the next launch opens on Home.
            FileHandle.standardError.write(Data("explorer-session.json not saved: \(error.localizedDescription)\n".utf8))
        }
    }
}
