import Foundation

/// Calls `onChange` (debounced 200 ms) when the CLI's state folder changes: the
/// CLI moves the state file and the log into place there, so a switch made in
/// the terminal shows up. Watches the folder, since the file may not exist yet;
/// while the folder itself is missing it watches the nearest existing parent
/// and moves down once the folder appears.
@MainActor
final class StateWatcher {
    private let folder: URL
    private let onChange: @MainActor () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var watched: URL?
    private var pending: Task<Void, Never>?

    init(file: URL, onChange: @escaping @MainActor () -> Void) {
        folder = file.deletingLastPathComponent().standardizedFileURL
        self.onChange = onChange
        arm()
    }

    private func arm() {
        var target = folder
        while !FileManager.default.fileExists(atPath: target.path), target.path != "/" {
            target = target.deletingLastPathComponent()
        }
        if target == watched, source != nil { return }
        source?.cancel()
        source = nil
        let descriptor = open(target.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.changed() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
        watched = target
    }

    private func changed() {
        // The folder may have appeared (or gone): re-pick what to watch.
        if watched != folder || !FileManager.default.fileExists(atPath: folder.path) {
            watched = nil
            arm()
        }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            self?.onChange()
        }
    }
}
