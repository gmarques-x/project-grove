import Darwin
import Foundation

/// Whether a folder has something in it that the list would show (spec
/// §16): what gives a folder its chevron.
public enum FolderPeek {
    /// True when `folder` holds at least one item that would show. Reads at most until the first such item
    /// (never the whole folder, never below it). Nil when it can't be read.
    ///
    /// An item is hidden by `Entry.isHidden`'s rule (a dot-name, or the
    /// hidden flag) and counts only when `showHidden`. Any other item
    /// counts, a link included, wherever it leads. `folder` itself is not
    /// followed when it is a link (nil): the list gives a link no chevron,
    /// so a link loop is never looked through. Links on the way to it are
    /// followed, as everywhere (`/var` is `/private/var`).
    public static func hasContents(_ folder: URL, showHidden: Bool) -> Bool? {
        let descriptor = open(folder.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        // Takes the descriptor: `closedir` closes it.
        guard let directory = fdopendir(descriptor) else {
            close(descriptor)
            return nil
        }
        defer { closedir(directory) }
        while true {
            errno = 0
            guard let item = readdir(directory) else {
                // The end, or a read that failed part-way.
                return errno == 0 ? false : nil
            }
            let shows = withUnsafePointer(to: &item.pointee.d_name) { name in
                name.withMemoryRebound(to: CChar.self, capacity: Int(item.pointee.d_namlen) + 1) { name in
                    if name[0] == CChar(UInt8(ascii: ".")) {
                        // "." and "..", which are no items at all.
                        if name[1] == 0 || (name[1] == CChar(UInt8(ascii: ".")) && name[2] == 0) { return false }
                        return showHidden
                    }
                    return showHidden || !hasHiddenFlag(name, in: descriptor)
                }
            }
            if shows { return true }
        }
    }

    /// Whether the item named `name` in the folder open as `descriptor` has
    /// the hidden flag (`chflags hidden`). An item that went since the
    /// listing is taken as not hidden: the folder had it.
    private static func hasHiddenFlag(_ name: UnsafePointer<CChar>, in descriptor: Int32) -> Bool {
        var info = stat()
        guard fstatat(descriptor, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { return false }
        return info.st_flags & UInt32(UF_HIDDEN) != 0
    }
}
