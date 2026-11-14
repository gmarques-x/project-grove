import Foundation
import GroveExplorerCore

/// Has Finder move an item to the Trash, through Apple Events: for the
/// items of iCloud Drive and the CloudStorage folders, which macOS won't
/// let Grove Explorer move there itself. The worker waits for the answer.
struct AppleScriptFinderTrash: FinderTrash {
    /// Every script of the app runs here, one at a time: `NSAppleScript`
    /// isn't thread-safe.
    static let queue = DispatchQueue(label: "com.projectgrove.explorer.scripts")

    func trash(_ url: URL) -> Result<URL, FinderTrashError> {
        let source = CloudTrash.finderScript(for: url)
        return Self.queue.sync {
            var error: NSDictionary?
            let answer = NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error {
                // errAEEventNotPermitted: control of Finder isn't allowed.
                if error[NSAppleScript.errorNumber] as? Int == -1743 { return .failure(.notAllowed) }
                let message = error[NSAppleScript.errorMessage] as? String
                return .failure(.failed(message ?? "Finder didn't answer"))
            }
            guard let path = answer?.stringValue, !path.isEmpty else { return .failure(.unknownLocation) }
            return .success(URL(fileURLWithPath: path))
        }
    }
}
