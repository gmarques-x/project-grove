import AppKit
import GroveExplorerCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// The sidebar (spec §5): Favourites, iCloud and Locations under fine-print
/// captions, the Trash at the bottom. The row lit is the active pane's
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
                ForEach(Array(Place.Section.allCases.enumerated()), id: \.element) { number, section in
                    let rows = places.indices.filter { places[$0].section == section }
                    if section == .trash {
                        Spacer(minLength: GroveSpace.s8)
                    } else if !rows.isEmpty {
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
        .background(Color(theme.bg0))
        // A folder dropped on the sidebar itself, between or below its rows,
        // becomes a favourite; on a row it goes into that place.
        .onDrop(of: [.fileURL], delegate: FileDropDelegate(model: model, target: .favourites))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sidebar")
    }

    /// A section's name in small capitals; in the rail a line stands for it.
    @ViewBuilder private func caption(_ section: Place.Section, first: Bool) -> some View {
        if rail {
            if !first { Line().padding(.vertical, GroveSpace.s8) }
        } else {
            Text(verbatim: section.rawValue.uppercased())
                .font(GroveFont.mono(GroveType.finePrint)).tracking(1)
                .foregroundStyle(theme.quiet)
                .padding(.leading, GroveSpace.s8)
                .padding(.top, first ? GroveSpace.s4 : GroveSpace.s16).padding(.bottom, GroveSpace.s4)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func row(_ place: Place, lit: Bool, cursor: Bool) -> some View {
        let volume: Volume? = if case .volume(let volume) = place.kind { volume } else { nil }
        let busy = volume.map { model.ejecting.contains($0.id) } ?? false
        let pointed = hovered.wrappedValue == place.id
        // A drag of files is over the row: it would drop into this place.
        let marked = model.dropMark == .place(place.id)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: GroveSpace.s8) {
                icon(place)
                if !rail {
                    Text(verbatim: place.title)
                        .font(GroveFont.mono(GroveType.label))
                        .foregroundStyle(busy ? theme.quiet : Color(theme.fg))
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    if let volume, volume.ejectable { eject(volume, busy: busy) }
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
            .help(rail ? place.title : place.url.path)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(place.title)
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

    /// The favourite's id in the config, for a favourite's row.
    private func favourite(_ place: Place) -> String? {
        place.kind == .favourite ? String(place.id.dropFirst("favourite.".count)) : nil
    }

    /// Files dropped on a row go into its place; the Trash takes none
    /// (⌘⌫ is the way there).
    private func dropTarget(_ place: Place) -> FileDropDelegate.Target {
        place.kind == .trash ? .nothing : .folder(place.url, mark: .place(place.id), side: nil, tab: nil)
    }

    @ViewBuilder private func icon(_ place: Place) -> some View {
        switch place.kind {
        case .favourite:
            FolderIcon(mark: IconMap.mark(for: place.url, home: model.home))
        case .cloud:
            symbol(.cloud)
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

    /// The row an eject button is in: the pointer is still over that row when it leaves the button.
    private func place(_ volume: Volume) -> String { "volume." + volume.id }
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
