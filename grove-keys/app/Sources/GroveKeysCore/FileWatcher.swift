import Foundation

/// Calls `onChange` once per real change of `file`: a different modification
/// date or different contents. Watches the folder (rename saves) and the file
/// itself (in-place writes). All state lives on one serial queue.
public final class FileWatcher: @unchecked Sendable {
    private struct Stamp: Equatable { var date: Date?; var data: Data? }

    private let file: URL
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "grove-keys.file-watcher")
    private var folderSource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var started = false
    private var last = Stamp()
    private var ignore: Data?
    private var pending = false

    public init(file: URL, onChange: @escaping @Sendable () -> Void) {
        self.file = file
        self.onChange = onChange
    }

    /// Not to be called from `onChange` (it runs on the watcher's queue; `queue.sync` would deadlock).
    public func start() {
        queue.sync {
            guard !started else { return }
            started = true
            last = stamp()
            folderSource = watch(file.deletingLastPathComponent(), mask: .write)
            watchFile()
        }
    }

    deinit { folderSource?.cancel(); fileSource?.cancel() }

    /// Not to be called from `onChange` (it runs on the watcher's queue; `queue.sync` would deadlock).
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

    private func watch(_ url: URL, mask: DispatchSource.FileSystemEvent) -> DispatchSourceFileSystemObject? {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: mask, queue: queue)
        source.setEventHandler { [weak self] in self?.changed() }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    /// The file's own descriptor follows the old inode after a rename save, so
    /// it is opened again after every event.
    private func watchFile() {
        fileSource?.cancel()
        fileSource = watch(file, mask: [.write, .extend, .delete, .rename])
    }

    private func cancelAll() {
        folderSource?.cancel(); fileSource?.cancel()
        folderSource = nil; fileSource = nil
        started = false
    }

    /// Events are gathered for 50 ms so a truncate-then-write save counts once.
    private func changed() {
        guard started, !pending else { return }
        pending = true
        queue.asyncAfter(deadline: .now() + .milliseconds(50)) { [weak self] in self?.check() }
    }

    private func check() {
        pending = false
        guard started else { return }
        watchFile()
        let now = stamp()
        guard now != last else { return }
        last = now
        if let skip = ignore, skip == now.data { ignore = nil; return }
        onChange()
    }
}
