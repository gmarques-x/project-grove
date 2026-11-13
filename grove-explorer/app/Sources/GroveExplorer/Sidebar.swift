import AppKit
import GroveExplorerCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// The sidebar (spec §5): Favourites, iCloud, a section for each cloud
/// provider (OneDrive…), the saved shares (Shared) and Locations under
/// fine-print captions, the Trash
/// at the bottom. The row lit is the active pane's
/// place. As a rail (a narrow window) it is the icons alone, the sections
/// divided by lines and the names in tooltips.
struct Sidebar: View {
    @ObservedObject var model: AppModel
    let rail: Bool
    @Environment(\.theme) private var theme
    /// The row under the pointer. `State` used directly: no SwiftUI macros here.
    private var hovered = State<String?>(initialValue: nil)

    init(model: AppModel, rail: Bool) {
        self.model = model
        self.rail = rail
    }

    var body: some View {
        let places = model.places
        let lit = model.litPlace(among: places)
        // Not drawn from: where a refused eject's reason goes (`ejectRefused`).
        let _ = (model.reach.sidebarIsRail = rail)
        VStack(alignment: .leading, spacing: 0) {
            Line()
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(sections(of: places).enumerated()), id: \.element) { number, section in
                    let rows = places.indices.filter { places[$0].section == section }
                    if section == .trash {
                        Spacer(minLength: GroveSpace.s8)
                    } else {
                        caption(section, first: number == 0)
                    }
                    ForEach(rows, id: \.self) { index in
                        row(places[index], lit: index == lit, cursor: index == model.sidebarCursor)
                    }
                }
            }
            .padding(GroveSpace.s8)
        }
        .frame(width: rail ? SidebarLayout.Mode.rail.width : SidebarLayout.Mode.full.width)
        // Only its own rectangle: a fill that reaches into the title bar's
        // safe area (the default) would paint over the window's header.
        .background(Color(theme.bg0), ignoresSafeAreaEdges: [])
        // A folder dropped on the sidebar itself, between or below its rows,
        // becomes a favourite; on a row it goes into that place.
        .onDrop(of: [.fileURL], delegate: FileDropDelegate(model: model, target: .favourites))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sidebar")
    }

    /// The sections that have rows, in the order of the rows (the places
    /// are listed section by section).
    private func sections(of places: [Place]) -> [Place.Section] {
        var seen: [Place.Section] = []
        for place in places where !seen.contains(place.section) { seen.append(place.section) }
        return seen
    }

    /// A section's name in small capitals; in the rail a line stands for it.
    @ViewBuilder private func caption(_ section: Place.Section, first: Bool) -> some View {
        if rail {
            if !first { Line().padding(.vertical, GroveSpace.s8) }
        } else {
            HStack(spacing: GroveSpace.s8) {
                Text(verbatim: section.caption.uppercased())
                    .font(GroveFont.mono(GroveType.finePrint)).tracking(1)
                    .foregroundStyle(theme.quiet)
                    .accessibilityAddTraits(.isHeader)
                if section == .shared {
                    Spacer(minLength: 0)
                    connectButton
                }
            }
            .padding(.leading, GroveSpace.s8)
            .padding(.trailing, section == .shared ? GroveSpace.s8 : 0)
            .padding(.top, first ? GroveSpace.s4 : GroveSpace.s16).padding(.bottom, GroveSpace.s4)
        }
    }

    /// The SHARED header's +: Connect to Server… (⌘K). Quiet, the text's
    /// colour under the pointer. Its own line height: the caption's row
    /// keeps the fine-print size.
    private var connectButton: some View {
        let pointed = hovered.wrappedValue == Self.connectID
        return Button { model.showConnectSheet() } label: {
            GroveIcon(.add, size: GroveType.finePrint)
                .foregroundStyle(pointed ? Color(theme.fg) : theme.quiet)
                .frame(width: IconMetrics.cell, height: GroveType.finePrint)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { hovered.wrappedValue = Self.connectID } else if hovered.wrappedValue == Self.connectID { hovered.wrappedValue = nil }
        }
        .accessibilityLabel("Connect to Server")
        .help("Connect to Server…")
    }

    private static let connectID = "connect"

    private func row(_ place: Place, lit: Bool, cursor: Bool) -> some View {
        let share = model.shareState(place)
        // A share's own volume, while it is connected: its eject is the row's.
        let volume: Volume? = switch place.kind {
        case .volume(let volume): volume
        case .share(let server) where place.url != nil: model.shareVolumes()[server.id]
        default: nil
        }
        let busy = volume.map { model.ejecting.contains($0.id) } ?? false
        // A share not connected is said in quiet text, its host after its name.
        let quiet = busy || (share != nil && place.url == nil)
        let pointed = hovered.wrappedValue == place.id
        // A drag of files is over the row: it would drop into this place.
        let marked = model.dropMark == .place(place.id)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: GroveSpace.s8) {
                icon(place)
                if !rail {
                    Text(verbatim: place.title)
                        .font(GroveFont.mono(GroveType.label))
                        .foregroundStyle(quiet ? theme.quiet : Color(theme.fg))
                        .lineLimit(1).truncationMode(.middle)
                        .layoutPriority(1)
                    if case .share(let server) = place.kind, !server.host.isEmpty {
                        Text(verbatim: server.host)
                            .font(GroveFont.mono(GroveType.body))
                            .foregroundStyle(theme.quiet)
                            .lineLimit(1).truncationMode(.tail)
                    }
                    Spacer(minLength: 0)
                    if share == .connecting, case .share(let server) = place.kind {
                        connecting(server)
                    } else if let volume, volume.ejectable {
                        eject(volume, busy: busy)
                    }
                }
            }
            .padding(.horizontal, GroveSpace.s8)
            .frame(maxWidth: .infinity, alignment: rail ? .center : .leading)
            .frame(height: BarMetrics.control)
            .background(
                lit ? theme.selectedFill(on: .base) : pointed || marked ? theme.hoverFill(on: .base) : .clear,
                in: RoundedRectangle(cornerRadius: GroveRadius.control))
            .lightOutline(cornerRadius: GroveRadius.control, when: lit && !marked)
            .dropOutline(marked)
            // The keyboard is here (⌥⌘←): the focus box, on the row's edge.
            .focusBox(cursor, cornerRadius: GroveRadius.control, outset: 0)
            .contentShape(Rectangle())
            .onTapGesture { model.open(place, inNewTab: NSEvent.modifierFlags.contains(.command)) }
            .onHover { inside in
                if inside { hovered.wrappedValue = place.id } else if hovered.wrappedValue == place.id { hovered.wrappedValue = nil }
            }
            .help(rail ? place.title : place.url?.path ?? shareAddress(place))
            .accessibilityElement(children: .contain)
            // A share says where it is and its state: "media on grove-lab, shared folder, connected".
            .accessibilityLabel(spoken(place, share))
            .accessibilityAddTraits(lit ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { model.open(place) }
            // The same rows a key opens (⌃Return with the keyboard here).
            .contextMenu {
                ForEach(model.menuRows(for: place)) { row in Button(row.title) { row.run() } }
            }
            .background { if cursor { MenuAnchor(model: model).allowsHitTesting(false) } }
            .onDrop(of: [.fileURL], delegate: FileDropDelegate(model: model, target: dropTarget(place)))
            .draggedOut(favourite(place), model: model)
            // The eject that failed (spec §13): why, under the row, until the next try.
            if let volume, let failure = model.ejectFailures[volume.id], !rail {
                theme.marked(failure, theme.orange, size: GroveType.finePrint)
                    .font(GroveFont.mono(GroveType.finePrint))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, GroveSpace.s8 + IconMetrics.cell + GroveSpace.s8)
                    .padding(.trailing, GroveSpace.s8)
                    .padding(.top, GroveSpace.s2).padding(.bottom, GroveSpace.s4)
            }
        }
    }

    /// What VoiceOver says of a row: its name; a share's with its host and state.
    private func spoken(_ place: Place, _ share: SharedRowState?) -> String {
        if case .share(let server) = place.kind, let share { return share.spoken(server) }
        return place.title
    }

    /// A share's address, for the tooltip of its row while it has no folder.
    private func shareAddress(_ place: Place) -> String {
        if case .share(let server) = place.kind { return server.url.absoluteString }
        return place.title
    }

    /// The favourite's id in the config, for a favourite's row.
    private func favourite(_ place: Place) -> String? {
        place.kind == .favourite ? String(place.id.dropFirst("favourite.".count)) : nil
    }

    /// Files dropped on a row go into its place; the Trash takes none
    /// (⌘⌫ is the way there).
    private func dropTarget(_ place: Place) -> FileDropDelegate.Target {
        // A share not connected has no folder to drop into.
        guard place.kind != .trash, let url = place.url else { return .nothing }
        return .folder(url, mark: .place(place.id), side: nil, tab: nil)
    }

    @ViewBuilder private func icon(_ place: Place) -> some View {
        switch place.kind {
        case .favourite:
            if let url = place.url { FolderIcon(mark: IconMap.mark(for: url, home: model.home)) }
        case .share:
            // Quiet unless connected.
            GroveIcon(.server, size: GroveType.label)
                .foregroundStyle(place.url == nil ? theme.quiet : Color(theme.fg))
                .frame(width: IconMetrics.cell, height: IconMetrics.cell)
        case .cloud:
            symbol(place.section == .cloud ? .cloud : .cloudStorage)
        case .trash:
            symbol(.trash)
        case .volume(let volume):
            Image(nsImage: model.volumeIconStandIn[volume.id] ?? IconCache.shared.volumeIcon(volume.url))
                .resizable().interpolation(.high)
                .frame(width: IconMetrics.cell, height: IconMetrics.cell)
                .accessibilityHidden(true)
        }
    }

    private func symbol(_ name: GroveIcon.Name) -> some View {
        GroveIcon(name, size: GroveType.label)
            .foregroundStyle(Color(theme.fg))
            .frame(width: IconMetrics.cell, height: IconMetrics.cell)
    }

    /// The eject button; the system's small spinner in its place while the disk is being ejected.
    @ViewBuilder private func eject(_ volume: Volume, busy: Bool) -> some View {
        if busy {
            ProgressView().controlSize(.mini)
                .frame(width: IconMetrics.cell, height: IconMetrics.cell)
                .accessibilityLabel("Ejecting \(volume.name)")
        } else {
            let pointed = hovered.wrappedValue == "eject." + volume.id || model.ejectPointerStandIn == volume.id
            Button { model.eject(volume) } label: {
                GroveIcon(.eject, size: GroveType.finePrint)
                    .foregroundStyle(pointed ? Color(theme.fg) : theme.quiet)
                    .frame(width: IconMetrics.cell, height: IconMetrics.cell)
                    .background(
                        pointed ? theme.selectedFill(on: .base) : .clear,
                        in: RoundedRectangle(cornerRadius: GroveRadius.inline))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { inside in
                let id = "eject." + volume.id
                if inside { hovered.wrappedValue = id } else if hovered.wrappedValue == id { hovered.wrappedValue = place(volume) }
            }
            .accessibilityLabel("Eject \(volume.name)")
            .help("Eject \(volume.name)")
        }
    }

    /// The system's small spinner where a connected share's eject goes;
    /// a click on it gives the mount up.
    private func connecting(_ server: SharedServer) -> some View {
        Button { model.cancelConnect(server) } label: {
            ProgressView().controlSize(.mini)
                .frame(width: IconMetrics.cell, height: IconMetrics.cell)
                .contentShape(Rectangle())
                // The button is what VoiceOver meets and presses, not a busy indicator.
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cancel connecting to \(server.name)")
        .help("Cancel connecting to \(server.name)")
    }

    /// The row an eject button is in: the pointer is still over that row
    /// when it leaves the button (a share's row, for a share's volume).
    private func place(_ volume: Volume) -> String {
        if let id = model.shareVolumes().first(where: { $0.value.id == volume.id })?.key { return "share." + id }
        return "volume." + volume.id
    }
}

extension View {
    /// The mark of the place a drag of files would drop into: a 1 pt green
    /// line round the control (with the hover fill, which the caller draws).
    func dropOutline(_ marked: Bool) -> some View {
        overlay {
            if marked { DropOutline() }
        }
    }

    /// A favourite's row can be dragged out of the sidebar: let go over the
    /// panes, the favourite is removed (`WindowView`). What it carries is
    /// no file, so nothing takes it for one.
    @ViewBuilder fileprivate func draggedOut(_ favourite: String?, model: AppModel) -> some View {
        if let favourite {
            onDrag {
                model.drags.favourite = favourite
                let provider = NSItemProvider()
                provider.registerDataRepresentation(
                    forTypeIdentifier: AppModel.favouriteDrag.identifier, visibility: .ownProcess
                ) { done in
                    done(Data(favourite.utf8), nil)
                    return nil
                }
                return provider
            }
        } else {
            self
        }
    }
}

private struct DropOutline: View {
    @Environment(\.theme) private var theme

    var body: some View {
        RoundedRectangle(cornerRadius: GroveRadius.control).strokeBorder(Color(theme.green), lineWidth: 1)
    }
}
