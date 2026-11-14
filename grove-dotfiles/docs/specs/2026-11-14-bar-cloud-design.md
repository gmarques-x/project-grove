# Bar: the cloud storage pill

Date: 2026-11-14. Status: approved in conversation; written up for the owner's review.

## Intent
The owner wants, from the Grove bar: to know his files **finished syncing**, **quick access** to his cloud folders, and a way to **their settings**. Providers today: iCloud Drive and OneDrive (OneDrive-Personal on this Mac; a work account would be another `OneDrive-<Company>` folder).

Success: one glance at the pill says "everything is synced" or not; one click opens a dropdown that says what is pending or wrong per provider, opens the folder in Grove Explorer, or opens the provider's settings.

## Goals, non-goals, anti-goals
- Goals: a cloud pill with three states (synced / syncing with a count / problem); a dropdown per provider with its status line, the pending or failed files (up to five, click reveals in Grove Explorer), "Open in Grove Explorer", "Settings…".
- Non-goals: pausing or resuming sync (no outside control exists: OneDrive has no command for it, iCloud's controls are private); storage quotas or account details (they need a sign-in to the provider's servers); any provider other than those under `~/Library/Mobile Documents/com~apple~CloudDocs` and `~/Library/CloudStorage`.
- Anti-goals: walking whole cloud trees on a timer (cost, battery); reading `fileproviderctl` output (an undocumented debugging tool); triggering downloads of online-only files just by looking at them.

## Approaches (the owner picked 1)
1. **Watch for changes, then follow only those files.** File-system events on each cloud root; for each changed item, read its URL resource values (`isUbiquitousItem`, `ubiquitousItemIsUploading`, `ubiquitousItemIsUploaded`, `ubiquitousItemIsDownloading`, `ubiquitousItemDownloadingStatus`, `ubiquitousItemUploadingError`, `ubiquitousItemDownloadingError`, `ubiquitousItemHasUnresolvedConflicts`) and keep it in a pending set until it settles; one low-priority background pass at login to catch what was pending before. **Chosen:** accurate within seconds, almost free after the first pass.
2. Walk every folder every few minutes: rejected — tens of thousands of files per pass, always minutes behind.
3. Parse `fileproviderctl`: rejected — undocumented, slow, changes between macOS versions.

## Design
**Pill.** Its own pill with a cloud SF Symbol, order `cpu/mem · cloud · vpn · wifi+bt · sound · power · clock`. States, coloured by meaning (not a per-pill hue): synced — `checkmark.icloud`-style cloud in green; syncing — `arrow.triangle.2.circlepath.icloud`-style in yellow with the pending count as the pill's label (hidden when 0); problem — `exclamationmark.icloud`-style in red (an upload/download error, an unresolved conflict, or a provider folder present but its app not running). Icons from `config/sketchybar/icons/make.swift`, dark and light, as the other bar icons. Item `cloud`, pill `pill.cloud`, event `cloud_change`; Grove Keys writes `$GROVE_STATE/cloud` (one line: `checking`, `synced`, `syncing <n>` or `problem`) only when it changes, as the Bluetooth file, and removes it when it stops. A missing or unreadable file shows a grey cloud (as Bluetooth's missing file shows off). The count is the number of pending files (uploads and downloads together) in a fixed-width label so the pill doesn't resize; hidden at 0.

**Dropdown** (Grove Keys panel `cloud`, like the others), one section per provider, iCloud Drive first then each CloudStorage folder. Names and order come from Grove Explorer's `FolderName` provider rule, which moves into grove-themes' GroveThemesCore so both apps share one rule (Grove Explorer imports it from there). Any CloudStorage provider gets a section and status; "not running" and "Settings…" exist only for iCloud and OneDrive (others show "Open in Grove Explorer" only):
- header: the provider's name and its status line — "Up to date", "Uploading 3 files · Downloading 1", "1 problem" (worst first), or "OneDrive isn't running";
- up to five rows of pending or failed files: name, its folder in quiet text, a problem line in the warning yellow / error red; clicking a row opens Grove Explorer at that item with `groveexplorer://open?path=<percent-encoded path>` (a file opens its folder with the file selected);
- "Open in Grove Explorer" (the provider's root) and "Settings…":
  - iCloud → `x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings` (community-known, not documented by Apple; checked by hand; if it fails, plain System Settings).
  - OneDrive (`com.microsoft.OneDrive`) → its Settings window via Accessibility, as the VPN's "Manage Tunnels…": press OneDrive's menu-bar item; if what opens is a menu with a settings item, press it; if it is OneDrive's activity window, find its settings button by role/title in that window. Fallback (anything not found, or Accessibility refused): activate OneDrive and show a yellow line "Open OneDrive's settings from its activity window". This path can only be proven by hand.

**Tracking (Grove Keys, off the main thread).**
- Roots: `~/Library/Mobile Documents/com~apple~CloudDocs` (if present) and every directory in `~/Library/CloudStorage`; watched for roots appearing/disappearing too.
- FSEvents per root (file-level events, coalesced ~1 s). Each changed path: read the resource values above; an item that is uploading, downloading, not yet uploaded, or has an error/conflict joins the pending set; pending items are re-read every 5 s (and on their next event) until they settle, then leave the set. Directories are expanded only for event paths, never walked whole after the first pass.
- **What counts as pending** (per item, files only — folders never count): uploading, or a ubiquitous item not yet uploaded, or a download actually in progress (`ubiquitousItemIsDownloading`). An online-only file (`downloadingStatus == .notDownloaded`) is normal and never pending; `.downloaded` (a newer version on the server, not being fetched) is not pending either. An item with an upload/download error or an unresolved conflict is a **problem**.
- **Items that never settle:** names the providers never sync are ignored outright (`.DS_Store`, `._*`, `*.nosync`, `~$*` lock files, `*.tmp`). An item still pending after 30 minutes without any change becomes a problem ("not uploading for 30 min"), which also catches a paused or signed-out OneDrive. Re-reads back off: every 5 s for the first 2 minutes, then every 60 s. The set is capped at 2,000 items (the count then reads "2000+").
- **Fresh reads:** every re-read uses a fresh URL or `removeAllCachedResourceValues()` (URL caches resource values). An upload finishing may produce no file event, so the timed re-reads are what settles items.
- **Never materialize anything:** the first pass and any directory expansion run on a thread with `setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD, IOPOL_MATERIALIZE_DATALESS_FILES_OFF)` and skip directories whose `st_flags` has `SF_DATALESS` (an online-only folder can't hold local edits waiting to upload). Only resource values / stat are read — never contents, never coordinated reads, never thumbnails.
- **First pass at login:** that walk, low priority and rate-capped; until it finishes the pill shows a grey "checking" cloud.
- A provider is "not running" when its root exists but its app process isn't running (OneDrive's bundle id; iCloud: `bird` is always there, so iCloud is never "not running").
- Pure Core with tests: the per-item state from resource values; a provider's summary from its items; the overall pill state and count; the status line's words; the five rows chosen (problems first, then most recent).

**Permission.** Reading file metadata under `~/Library/CloudStorage` may make macOS ask once whether Grove Keys may access files managed by OneDrive; that prompt is the owner's. Refused: the provider's section says "Grove Keys can't see OneDrive's files" with a button to the privacy setting; the pill ignores that provider.

## Constraints
grove-ui rules; JetBrains Mono; renders of the pill states and the dropdown (synced, syncing with files, a problem, a provider not running) in dark and light into `~/Developer/artifacts/sketchybar/renders/cloud/`; no real file names or account names in committed samples, fixtures or docs (public repo); the GroveKeys binary only with its render/check flags; never move, open or download the owner's cloud files.

## Calls made in writing this (for the owner to check)
- Online-only files never count as "not synced"; only uploads, unfinished uploads and active downloads do.
- Files stuck for 30 minutes turn the pill red; never-synced names (.DS_Store and the like) are ignored.
- A grey "checking" cloud at login until the first pass finishes, and grey when Grove Keys isn't running.
- Other CloudStorage providers (Dropbox, Google Drive…) get a section if they appear, without Settings.
- The folder-naming rule moves into the shared grove-themes package so Grove Keys and Grove Explorer name providers the same way.
- iCloud's settings link is a known-but-undocumented System Settings link; OneDrive's settings are reached through its menu-bar icon, with a fallback line.

## Left to the builder
FSEvents vs DispatchSource details, the pending set's data structure, exact SF Symbol names, how the first pass is throttled.
