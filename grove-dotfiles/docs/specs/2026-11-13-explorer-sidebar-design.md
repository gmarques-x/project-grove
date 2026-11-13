# Grove Explorer: one LOCATIONS list, and a sidebar you can widen

Date: 2026-11-13. Status: approved in conversation (short design).

## A. Shares live under LOCATIONS
Owner: "I want everything under locations and the + for new shares in front of locations, drop the shared section."
- The SHARED section is gone. LOCATIONS lists, in order: the startup disk, other disks/volumes (as today), then the saved shares (as added), then mounted network volumes that aren't saved (as today, with "Keep in Sidebar").
- A saved share keeps every behaviour it had in SHARED: not connected (dimmed, click connects), connecting (spinner, click/Esc cancels), connected (eject; opens its folder), its quiet host text, VoiceOver label, "Remove from Sidebar", and a saved share's mount is still listed once (its share row, not a second volume row).
- The LOCATIONS header always carries the + ("Connect to Server…", same tooltip and VoiceOver label); ⌘K and File ▸ Connect to Server… stay.
- Shared-folders spec, manual and renders updated to match.

## B. The sidebar's width is adjustable
- Drag the line between the sidebar and the panes (resize-left-right pointer over it), 160–360 pt; double-click resets to 200.
- The panes take the rest and keep their left/right split ratio.
- The width is remembered with the window's state and restored at launch.
- The rail (48 pt) and hidden modes still switch on narrow windows; the threshold uses the chosen width, and the chosen width returns when the window widens again.
- The clamp, the switch-over points and the pane widths are pure Core logic (`SidebarLayout`) with tests; renders at 160 and 360, dark and light; `--audit-accessibility all` passes (the divider is an accessibility splitter with its value).

## As built (2026-11-13)

- A: `SidebarSection` (no `.shared`; only `.locations` carries the +) and `Locations.rows` (the order) are in Core with tests; the startup disk is the volume at `/`, a network volume is `volumeIsLocal` false.
- B: `SidebarLayout.clamped(width:)`, `width(of:chosen:)`, `mode(…chosen:)`, `panesWidth(…chosen:)`, `dragged(to:windowWidth:panes:)` and `reset`. A drag also stops where the panes would fall under 430 pt each, so the sidebar never turns into the rail under the pointer. The width is the session's `sidebarWidth` (the field was already there, always 200). Only the full sidebar's line is draggable; beside the rail it is a plain line.
- VoiceOver: the line is an `AXSplitter` "Sidebar width" whose value is the width in points (an AppKit view behind it that takes no clicks; SwiftUI has no splitter role); increment and decrement move it 20 pt. The pane divider is unchanged (an adjustable element).
- Renders: `shared` (Locations with the shares and an unsaved network volume last), `sidebar-160`, `sidebar-360`.
