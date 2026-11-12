import AppKit
import GroveExplorerCore
import Quartz

/// Quick Look for a pane's list (spec §7): Space shows the system's preview
/// panel for the selection and Space again puts it away; while it is up ↑
/// and ↓ move the list's selection and the panel follows; it opens out of
/// the row's icon and closes back into it.
///
/// The panel is the system's one shared panel. It asks the responder chain
/// who controls it: the list that has the keyboard says so
/// (`FileTableView` below) and lends it this object as its data source and
/// delegate until the panel closes or the keyboard goes to another list.
@MainActor
final class QuickLookController: NSObject, @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
    private let model: AppModel
    private let side: Side
    weak var table: FileTableView?
    /// The items the panel was last told of, in the list's order.
    private var shown: [URL] = []
    /// The panel is this list's for now.
    private var controls = false

    init(model: AppModel, side: Side) {
        self.model = model
        self.side = side
    }

    /// The pane's selected items that its list shows, in the list's order.
    private var items: [URL] {
        let chosen = model.selection(for: side)
        return chosen.isEmpty ? [] : model.entries(for: side).filter { chosen.contains($0.url) }.map(\.url)
    }

    /// The panel, when it is up and this list's.
    private var panel: QLPreviewPanel? {
        guard controls, QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(),
            panel.dataSource === self
        else { return nil }
        return panel
    }

    // MARK: The list lends itself

    func begin(_ panel: QLPreviewPanel) {
        controls = true
        shown = items
        panel.dataSource = self
        panel.delegate = self
    }

    func end(_ panel: QLPreviewPanel) {
        controls = false
        shown = []
        // The panel doesn't keep what it points at alive: never left pointing here.
        if panel.dataSource === self { panel.dataSource = nil }
        if panel.delegate === self { panel.delegate = nil }
    }

    /// The list is going (its pane closed): the panel, if it is this
    /// list's, is put away and let go of.
    func detach() {
        guard controls, QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared() else { return }
        let ours = panel.dataSource === self
        end(panel)
        if ours, panel.isVisible { panel.orderOut(nil) }
    }

    /// The list's selection changed: the panel shows the new one.
    func selectionChanged() {
        guard let panel, panel.isVisible else { return }
        let now = items
        guard now != shown else { return }
        shown = now
        panel.reloadData()
    }

    // MARK: The panel asks

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { shown.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        shown.indices.contains(index) ? shown[index] as NSURL : nil
    }

    /// ↑ and ↓ (with ⇧ too) pressed in the panel are the list's: they move
    /// its selection. Every other key stays the panel's own (Space and
    /// Escape close it, ⌘W too: `ExplorerApp`'s monitor lets it through).
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard let event, event.type == .keyDown, let table, table.window != nil,
            let stroke = CommandTable.stroke(of: event), stroke.key == "↑" || stroke.key == "↓",
            stroke.modifiers.isSubset(of: [.shift])
        else { return false }
        table.keyDown(with: event)
        return true
    }

    /// Where the panel zooms from and back to: the row's icon, on the
    /// screen. Nowhere (a plain fade) for an item whose row isn't in view.
    func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: (any QLPreviewItem)!) -> NSRect {
        guard let table, let window = table.window, let url = item?.previewItemURL,
            let row = model.listing(for: side)?.rows[url], row < table.numberOfRows
        else { return .zero }
        let rowRect = table.rect(ofRow: row)
        guard table.visibleRect.intersects(rowRect) else { return .zero }
        let cell = IconMetrics.cell
        let icon = NSRect(
            x: ListColumns.edge, y: rowRect.minY + ((rowRect.height - cell) / 2).rounded(), width: cell, height: cell)
        return window.convertToScreen(table.convert(icon, to: nil))
    }
}

extension FileTableView {
    // The system asks each responder, from the one with the keyboard up,
    // whether the preview panel is its to fill. It asks on the main
    // thread, through methods every object has, which say nothing of that.

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        MainActor.assumeIsolated { quickLook != nil }
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            if let panel { quickLook?.begin(panel) }
        }
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            if let panel { quickLook?.end(panel) }
        }
    }
}

extension AppModel {
    /// The preview panel is on the screen.
    var quickLookIsUp: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared()?.isVisible == true
    }

    /// Space: shows the panel for the selection, or puts it away. The panel
    /// then finds the list that has the keyboard by itself.
    func toggleQuickLook() {
        guard live else { return }
        if quickLookIsUp {
            QLPreviewPanel.shared()?.orderOut(nil)
        } else if hasSelection {
            QLPreviewPanel.shared()?.makeKeyAndOrderFront(nil)
        }
    }
}
