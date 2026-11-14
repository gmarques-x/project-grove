# Grove Explorer: moving iCloud and cloud-storage items to the Trash

Date: 2026-11-14. Status: approved in conversation (the owner: "yes, go ahead").

## Intent
Grove Explorer can't move any item in iCloud Drive to the Trash: it fails with "you don't have permission". Finder can. The owner wants Explorer to trash these like everything else, with Undo.

## Root cause (measured on macOS 27.2)
- Moving an item inside a File Provider domain (iCloud Drive in `~/Library/Mobile Documents`, and the `~/Library/CloudStorage` providers such as OneDrive) to the Trash needs the `kTCCServiceFileProviderDomain` permission. The system log says: `sandboxd rejected approval request from GroveExplorer for kTCCServiceFileProviderDomain (…): would require prompt`. The Trash call may not prompt, so the permission is never asked for and the call fails with `NSFileWriteNoPermissionError` (513).
- The file's mode, whether it is downloaded, Intune tags and Full Disk Access make no difference. `FileManager.trashItem` and `NSWorkspace.recycle` both fail. A process started from a terminal works, because the terminal holds the permission.
- Finder can do it: `tell application "Finder" to delete (POSIX file "…")` moves the item and returns the item in the Trash, whose POSIX path is known.
- Moving the item back out of the Trash (Undo) and renaming items in iCloud Drive work from Explorer as they are. Only the move into the Trash is refused.
- Another developer found the same refusal and the same fix: github.com/fum1h1ro/miata pull request 39.

## Goals, non-goals, anti-goals
- Goals: trashing an item in iCloud Drive or a CloudStorage folder works from Explorer, Undo puts it back, and a refusal says what to do.
- Non-goals: asking for any new permission; changing how items elsewhere go to the Trash; trashing through Finder anywhere it isn't needed.
- Anti-goals: changing file modes or tags; simulated keystrokes; Finder windows opening or coming forward.

## Approaches (the owner chose A)
- **A. Fall back to Finder. Chosen:** Explorer tries `trashItem` first, as it does today. When that fails with a permission error (513) for an item inside a cloud folder, it asks Finder through Apple Events to move the item to the Trash, and records where Finder put it. Explorer already asks for "control Finder" for ⌘I, so no new permission is needed.
- B. Full Disk Access: tried and doesn't help, since it isn't the permission in question.
- C. A clearer message only: rejected, because the bug would stay.

## Design
- **Where:** `OperationWorker.moveToTrash`, the one place every trash goes through, including the Trash step of a replace. Behaviour outside cloud folders doesn't change.
- **Cloud folders:** a path under `~/Library/Mobile Documents/` or `~/Library/CloudStorage/`, resolved through the item's real path (standardised, symlinks resolved). The check is a pure function in GroveExplorerCore, with tests.
- **Finder step:** the script is built by a pure function next to `getInfoScript`, with the same escaping: `tell application "Finder"`, `set t to delete (POSIX file "<path>")`, `return POSIX path of (t as alias)`. It runs through `NSAppleScript` on one serial queue, because `NSAppleScript` isn't thread-safe. The worker waits for the answer. The step sits behind a small protocol, so tests use a fake and never drive Finder.
- **Results:**
  - Success: the item is trashed and Undo works as usual.
  - Error -1743, meaning control of Finder isn't allowed: the item fails with "Allow Grove Explorer to control Finder in Privacy Settings to move cloud items to the Trash".
  - Any other Finder error: the item fails with "Finder couldn't move it to the Trash: <message>".
  - An empty or unreadable path in Finder's answer: "it is in the Trash, but where there is not known", the existing wording.
- **Several items:** Finder is asked once per item. The usual count of cloud items in one trash is small, so per-item results are worth more than one combined script.
- **Docs:** the grove-explorer README permissions paragraph and manual 09 get one line each: cloud items go to the Trash through Finder, so ⌘⌫ there asks to control Finder the first time.

## Left to the builder
- The protocol's name and where the serial queue lives.
- Whether the cloud-folder check uses `FileManager`'s home or the `home:` the worker already has; follow what tests inject.
