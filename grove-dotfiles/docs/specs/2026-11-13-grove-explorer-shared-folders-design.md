# Grove Explorer: shared folders in the sidebar

Date: 2026-11-13. Status: design for the owner's review.

## Intent

The owner keeps SMB shares on grove-lab, his Proxmox host. Today a share only
appears in Grove Explorer if Finder mounted it, and it is gone from the sidebar
the moment it unmounts. He wants Grove Explorer itself to connect to a share
and keep it in the sidebar, so getting back to it is one click, without Finder.

Success: he adds `smb://grove-lab/<share>` once; from then on it sits in the
sidebar, a click mounts it (asking for the password only if macOS hasn't
remembered it) and opens it in the pane, and after a restart it is still there.

## Goals, non-goals, anti-goals

- Goals: a SHARED sidebar section; "Connect to Server…" to add one; saved
  servers survive unmount and restart; one click reconnects; clear states
  (connected, not connected, connecting, failed and why); remove a saved one.
- Non-goals: SCP/SSH (dropped by the owner for now; Stage 4 stays its own
  spec); browsing grove-lab's list of shares before choosing one (the owner
  types the share's address); Bonjour/network neighbourhood discovery;
  auto-mount at login.
- Anti-goals: Grove Explorer ever seeing, storing or logging a password; a
  Finder window opening; a hung UI while a server doesn't answer.

## Approaches (the owner picked 1)

1. **NetFS (`NetFSMountURLAsync`)** — Finder's own Connect to Server path. macOS
   shows its standard authentication sheet with "Remember this password in my
   keychain", mounts under /Volumes, and returns the mount point; errors come
   back as codes. **Chosen:** native, passwords stay with macOS, the app learns
   where the share landed.
2. `open smb://…` / `NSWorkspace.open` — Finder mounts it and opens a Finder
   window. Rejected: the opposite of Grove Explorer's job.
3. `mount_smbfs` ourselves — the app would have to handle the password and the
   Keychain. Rejected: more code and risk for nothing gained.

## Design

**Sidebar.** A SHARED section below the cloud sections and above LOCATIONS,
shown when at least one share is saved; its header carries
a + (GroveIcon add, quiet, text colour on hover, `.help("Connect to Server…")`).
One row per saved share: the share's name (last path part of the URL, e.g.
"media"), with the host in quiet text after it ("media  grove-lab"), icon
`server.rack` (quiet when not connected). States, one value per row:

- **not connected**: name in quiet text; click → connect.
- **connecting**: a small spinner where the eject button goes; clicking the
  spinner (or Esc with the row focused) cancels (`NetFSMountURLCancel`), back
  to not connected, quietly.
- **connected**: normal text and an eject button (as Locations rows have);
  click → open the mount point in the pane, like any place; the row lights
  when the pane is inside it (the existing "deepest place wins" rule).
- **failed**: back to not connected, with the reason in the active pane's
  existing notice line ("grove-lab didn't answer", "The password was refused",
  "There is no share called media on grove-lab").

A share mounted by someone else (Finder, the command line) that matches a saved
one shows as connected on that row, and only there: a saved share's mount is
not listed again under LOCATIONS. A mounted network share that isn't saved stays
in LOCATIONS as today, with "Keep in Sidebar" in its context menu, which saves it.

Cancelling macOS's password sheet is quiet: the row (or the connect sheet)
goes back to how it was, with no notice.

**Connect to Server…** Reached from the SHARED header's +, from File ▸
Connect to Server… and with ⌘K (Finder's key; added to spec §7's table), so it
works before anything is saved. A small sheet (native `TextField` + buttons, Grove
tokens): "Server address" with placeholder `smb://grove-lab/share`, Connect and
Cancel. `smb://`, `afp://` and `nfs://` are accepted (NetFS handles all three;
grove-lab is SMB); a bare `grove-lab/media` gets `smb://` added. Connect mounts
first and saves only on success, so a typo isn't kept. While it connects the
sheet stays open with a spinner on Connect (Cancel cancels the mount); a
failure shows its sentence inside the sheet under the field, the address kept
so it can be corrected; success closes the sheet, saves the share and opens it
in the active pane. An address with a
password in it (`smb://user:pass@…`) is refused with "Leave the password out —
macOS will ask for it" and nothing is saved; a user name (`smb://you@grove-lab/media`)
is kept.

**Saving.** In the app-written `~/.config/grove-explorer/explorer.local.toml`
(main spec §9: the app writes only the local file; `explorer.toml` is the
tracked default and never holds a hostname). Grove's TOML reader has no arrays
of tables, so each share is a table like the favourites: `[servers.<id>]` with
`url = "smb://grove-lab/media"` and `order = N`, `<id>` a slug of host and
share (`grove-lab-media`, `-2` on a clash). The tracked file has no
`[servers]`; the list is the local file's alone (nothing to merge). Removing:
the row's context menu "Remove from Sidebar" forgets the share and does not
eject it; if it is mounted, it moves to LOCATIONS, where it can be ejected or
kept again. Order: as added; drag to reorder is not in scope.

**Connecting.** `NetFSMountURLAsync` with the URL, `nil` mount path (macOS picks
/Volumes/<share>), the default open options (so macOS shows its authentication
UI and uses the Keychain), on a background queue; the result comes back to the
main actor. No timer of the app's own: the callback only comes when everything is
over, password sheet included, so a fixed limit would cut the owner off while
typing; macOS's own SMB timeout ends an unreachable server, and the spinner's
cancel ends anything sooner. Error codes mapped to the
sentences above in Core (pure, tested); unknown codes → "Couldn't connect to
<host> (error N)". Ejecting uses the existing eject path.

**What is pure Core (tested):** parsing and normalising an address (scheme
added, password refused, user kept, name and host for the row); the saved
list's read/write in explorer.toml; matching a mounted volume to a saved share
(by `volumeURLForRemountingKey`, falling back to host + share name); the row's
state from (saved, mounted, connecting, last error); error code → sentence,
with the user-cancelled code mapped to "quiet" (no sentence).

## Constraints

- grove-ui skill: SF Symbols through GroveIcon, theme roles only, JetBrains Mono.
- Not sandboxed (as today); macOS may ask once for network volumes (spec §
  permissions), which the owner chose to allow.
- Nothing about a password in logs, files, the status line or VoiceOver.
- VoiceOver: a row says "<name> on <host>, shared folder, connected / not
  connected / connecting"; the + says "Connect to Server".
- Renders for the owner (sidebar in each state, the sheet; dark and light)
  before install; `--audit-accessibility all` passes.

## Calls made in writing this (for the owner to check)

- Saved in explorer.local.toml as `[servers.<id>]` tables (the tracked file never gets a hostname).
- ⌘K and File ▸ Connect to Server…, as in Finder, so it works before anything is saved.
- The sheet stays open while connecting and shows a failure inside it.
- No app timeout; a cancel on the spinner instead.
- A saved share's mount shows only in SHARED, not again in LOCATIONS.
- Cancelling the password sheet is quiet.
- "Remove from Sidebar" forgets without ejecting.

## Left to the builder

A not-connected row has no folder yet, so the sidebar needs a place kind
without a URL; Return on a not-connected row connects; rail mode follows the
existing rows.

Also: the exact sheet layout within Grove's window style; the spinner's look;
where the address parser lives in Core; how the matching is cached.

## As built (2026-11-13)

Where the build differs from the design above:

- The sheet's spinner sits beside Connect (which is disabled), not inside it.
  Cancel while connecting gives the mount up and keeps the sheet and its
  address; a second Cancel (or Esc) closes it.
- A mounted volume is matched to a saved share by its remount address; the
  volume-name fallback is used only for a network volume macOS gives no
  remount address for, and never by Connect to Server's "already mounted"
  shortcut (`smb://other/media` must not open another server's `media`).
  One volume per share: a second mount of it (`media-1`) stays in LOCATIONS.
- "Keep in Sidebar" is offered only for a LOCATIONS volume whose remount
  address the sheet would take (smb, afp, nfs, naming a share) and that is
  not saved yet (`SharedServers.keepable`); WebDAV and FTP volumes get none.
- The row's state is (saved, mounted, connecting); a failure is not kept on
  the row: it is said once in the active pane's notice line.
- Network volumes in LOCATIONS have an eject button (unmount), as Finder's.
