import CoreServices
import Foundation

/// Calls `onChange` when what is in `folder` changes: an item made, renamed,
/// removed or written to, or the folder itself gone. Only the folder's own
/// level is watched; a change further down is not told.
///
/// Calls are gathered: the first change is told at once, those that follow
/// at most once per `latency`. `onChange` runs on the watcher's own queue.
/// One call may come right after `init` for a change made just before it
/// (FSEvents hands those to a new watcher, and they can't be told from new
/// ones); a caller that reads the folder again loses nothing by it.
public final class FolderWatcher: @unchecked Sendable {
    /// What the stream's callback works with. The stream keeps it alive, so
    /// a call on its way while the watcher goes still finds it.
    private final class Receiver {
        let path: String
        let onChange: @Sendable () -> Void
        /// Read and written on the watcher's queue only.
        var stopped = false

        init(path: String, onChange: @escaping @Sendable () -> Void) {
            self.path = path
            self.onChange = onChange
        }

        func received(_ paths: [String], _ flags: UnsafeBufferPointer<FSEventStreamEventFlags>) {
            guard !stopped else { return }
            if zip(paths, flags).contains(where: { FolderWatcher.tells($0, flags: $1, of: path) }) { onChange() }
        }
    }

    /// The folder moved or went, or FSEvents lost count and says to look again.
    private static let always = FSEventStreamEventFlags(
        kFSEventStreamEventFlagRootChanged | kFSEventStreamEventFlagMustScanSubDirs
            | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped
    )

    /// Whether an event is a change of `folder` (its real path, no slash at
    /// the end). An event names the folder whose contents changed, with a
    /// slash at its end: the watched one itself, or one somewhere beneath it.
    static func tells(_ event: String, flags: FSEventStreamEventFlags, of folder: String) -> Bool {
        if flags & always != 0 { return true }
        return (event.count > 1 && event.hasSuffix("/") ? String(event.dropLast()) : event) == folder
    }

    private let receiver: Receiver
    private let queue = DispatchQueue(label: "grove-explorer.folder-watcher")
    private let onQueue = DispatchSpecificKey<Bool>()
    /// Nil once stopped (or when FSEvents refused); changed on `queue` only.
    private var stream: FSEventStreamRef?

    public init(folder: URL, latency: TimeInterval = 0.3, onChange: @escaping @Sendable () -> Void) {
        // Events name real paths: a folder reached through a link (as all of
        // /var and /tmp are) is watched, and compared, where it really is.
        let path = realpath(folder.path, nil).map { resolved in
            defer { free(resolved) }
            return String(cString: resolved)
        } ?? folder.path
        receiver = Receiver(path: path, onChange: onChange)
        queue.setSpecific(key: onQueue, value: true)

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(receiver).toOpaque(),
            retain: { info in
                guard let info else { return nil }
                _ = Unmanaged<Receiver>.fromOpaque(info).retain()
                return info
            },
            release: { info in
                guard let info else { return }
                Unmanaged<Receiver>.fromOpaque(info).release()
            },
            copyDescription: nil
        )
        // Without the file-events flag an event is "something in this folder
        // changed", once per folder: a busy tree beneath the watched folder
        // costs a few events, not one per file. NoDefer tells the first
        // change at once instead of after the latency.
        let flags = kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer
            | kFSEventStreamCreateFlagWatchRoot
        guard let stream = FSEventStreamCreate(
            nil,
            { _, info, count, paths, flags, _ in
                guard let info else { return }
                let receiver = Unmanaged<Receiver>.fromOpaque(info).takeUnretainedValue()
                let paths = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
                receiver.received(paths, UnsafeBufferPointer(start: flags, count: count))
            },
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            FSEventStreamCreateFlags(flags)
        ) else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return
        }
        self.stream = stream
    }

    deinit { stop() }

    /// No call is made once this has returned. Safe to call twice, and from
    /// inside `onChange`. It waits for a call in progress to end, so
    /// `onChange` must not block on the thread that calls `stop()` (a
    /// `DispatchQueue.main.sync` in it, with `stop()` called on main).
    public func stop() {
        if DispatchQueue.getSpecific(key: onQueue) == true {
            close()
        } else {
            queue.sync { close() }
        }
    }

    /// On `queue`.
    private func close() {
        guard let stream else { return }
        receiver.stopped = true
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
