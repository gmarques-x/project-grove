import Foundation

/// Calls `onChange` once per real change of `file`: a different modification
/// date or different contents. Watches the folder (rename saves) and the file
/// itself (in-place writes). All state lives on one serial queue.
public final class FileWatcher: @unchecked Sendable {
    private struct Stamp: Equatable { var date: Date?; var data: Data? }

    private let file: URL
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "grove-keys.file-watcher")
    private var sources: [DispatchSourceFileSystemObject] = []
    private var last = Stamp()
    private var ignore: Data?
    private var pending = false

    public init(file: URL, onChange: @escaping @Sendable () -> Void) {
        self.file = file
        self.onChange = onChange
    }

    public func start() {
        queue.sync {
            guard sources.isEmpty else { return }
            last = stamp()
            watch(file.deletingLastPathComponent(), mask: .write)
            watchFile()
        }
    }

    public func stop() {
        queue.sync { cancelAll() }
    }

    /// The next change whose contents equal `contents` is skipped, once.
    public func ignoreNextChange(contents: Data) {
        queue.async { self.ignore = contents }
    }

    // Everything below runs on `queue`.

    private func stamp() -> Stamp {
        let date = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
        return Stamp(date: date, data: try? Data(contentsOf: file))
    }

    private func watch(_ url: URL, mask: DispatchSource.FileSystemEvent) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: mask, queue: queue)
        source.setEventHandler { [weak self] in self?.changed() }
        source.setCancelHandler { close(fd) }
        sources.append(source)
        source.resume()
    }

    /// The file's own descriptor follows the old inode after a rename save, so
    /// it is opened again after every event.
    private func watchFile() {
        if sources.count > 1 { sources.removeLast().cancel() }
        watch(file, mask: [.write, .extend, .delete, .rename])
    }

    private func cancelAll() {
        sources.forEach { $0.cancel() }
        sources = []
    }

    /// Events are gathered for 50 ms so a truncate-then-write save counts once.
    private func changed() {
        guard !sources.isEmpty, !pending else { return }
        pending = true
        queue.asyncAfter(deadline: .now() + .milliseconds(50)) { [weak self] in self?.check() }
    }

    private func check() {
        pending = false
        guard !sources.isEmpty else { return }
        watchFile()
        let now = stamp()
        guard now != last else { return }
        last = now
        if let skip = ignore, skip == now.data { ignore = nil; return }
        onChange()
    }
}
