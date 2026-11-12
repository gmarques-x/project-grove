import GroveThemesCore
import SwiftUI

/// What a file list draws its rows with. A list has a selection, the other
/// pane's selection and the pointer at once, so it takes its own three fills
/// (the theme files' `list_selected`, `list_selected_inactive`, `list_hover`)
/// and not `selectedFill`/`hoverFill`, which were tuned for one of each: in
/// every scheme the selection is the strongest and the hover the weakest.
extension ThemeColors {
    /// The fill of a selected row: `listSelected` in the pane that has the
    /// keys (`active`), `listSelectedInactive` in the other one.
    public func listSelectionFill(active: Bool) -> Color {
        Color(active ? listSelected : listSelectedInactive)
    }

    /// The fill of the row under the pointer: `listHover`.
    public var listHoverFill: Color { Color(listHover) }

    /// The name of a hidden item: `hiddenInk`, never an opacity.
    public var hiddenText: Color { Color(hiddenInk) }
}
