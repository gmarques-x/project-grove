import GroveThemesCore
import SwiftUI

// Grove's one command-palette component (macOS has none): a panel over the
// screen (`KeyPanelHost`) with a field to filter in (`FilterField`), a card
// (`KeyPanelView`) and rows walked with ↑/↓ (`KeyPanelList`,
// `KeyPanelSelection`). The Grove Launcher and the searchable cheat sheet are
// both made of it; a new one supplies its rows and what Return does.

extension View {
    /// The card of the cheat sheets and the launcher, on the scrim: bg0 a
    /// little see-through, a `border` outline, a shadow.
    public func sheetCard(_ theme: ThemeColors) -> some View {
        background(theme.sheetFill, in: RoundedRectangle(cornerRadius: GroveRadius.window))
            .overlay(RoundedRectangle(cornerRadius: GroveRadius.window).strokeBorder(theme.line, lineWidth: 1))
            .shadow(color: theme.cardShadow, radius: 30, y: 15)
    }
}

/// Where a key panel's card sits on the screen.
public enum KeyPanelPlacement {
    /// `width` wide and as tall as its rows, its top edge `fraction` of the
    /// screen's height down: from a fixed height, so the field stays put as
    /// the list shrinks.
    case hanging(width: CGFloat, fraction: CGFloat)
    /// In the middle, `width` by `height`; on a smaller screen, what leaves
    /// 24 pt clear at each side and 48 above and below.
    case centred(width: CGFloat, height: CGFloat)
}

/// A key panel's content, to hand to `KeyPanelHost.open`: the scrim (a click
/// on it closes) and the card with the field, a line, then `content` (the
/// rows, or what stands for none). `hint` sits at the field's right.
/// ↑/↓, Return and Escape come from the field; the owner moves its
/// `KeyPanelSelection` and runs the row.
public struct KeyPanelView<Hint: View, Content: View>: View {
    let theme: ThemeColors
    let placement: KeyPanelPlacement
    let query: String
    let placeholder: String
    let onQuery: @MainActor (String) -> Void
    let onMove: @MainActor (Int) -> Void
    let onReturn: @MainActor () -> Void
    let onClose: @MainActor () -> Void
    let hint: Hint
    let content: Content

    /// The field's row.
    public static var fieldHeight: CGFloat { 46 }

    public init(theme: ThemeColors, placement: KeyPanelPlacement, query: String, placeholder: String,
                onQuery: @escaping @MainActor (String) -> Void, onMove: @escaping @MainActor (Int) -> Void,
                onReturn: @escaping @MainActor () -> Void, onClose: @escaping @MainActor () -> Void,
                @ViewBuilder hint: () -> Hint, @ViewBuilder content: () -> Content) {
        self.theme = theme
        self.placement = placement
        self.query = query
        self.placeholder = placeholder
        self.onQuery = onQuery
        self.onMove = onMove
        self.onReturn = onReturn
        self.onClose = onClose
        self.hint = hint()
        self.content = content()
    }

    public var body: some View {
        GeometryReader { screen in
            switch placement {
            case .hanging(let width, let fraction):
                ZStack(alignment: .top) {
                    scrim
                    card.frame(width: width).sheetCard(theme)
                        .padding(.top, screen.size.height * fraction)
                }
            case .centred(let width, let height):
                ZStack {
                    scrim
                    card.frame(width: min(width, screen.size.width - 2 * GroveSpace.s24),
                               height: min(height, screen.size.height - 4 * GroveSpace.s24))
                        .sheetCard(theme)
                }
            }
        }
        .font(GroveFont.mono(GroveType.heading))
        .environment(\.theme, theme)
        .preferredColorScheme(theme.colorScheme)
    }

    private var scrim: some View {
        theme.scrim
            .contentShape(Rectangle())
            .onTapGesture { onClose() }
    }

    private var card: some View {
        VStack(spacing: 0) {
            HStack(spacing: GroveSpace.s12) {
                FilterField(text: query, placeholder: placeholder, theme: theme,
                            onChange: onQuery, onMove: onMove, onReturn: onReturn, onEscape: onClose)
                hint
            }
            .padding(.horizontal, GroveSpace.s16)
            .frame(height: Self.fieldHeight)
            Rectangle().fill(theme.line).frame(height: 1)
            content
        }
    }
}

extension KeyPanelView where Hint == EmptyView {
    /// Without a hint beside the field.
    public init(theme: ThemeColors, placement: KeyPanelPlacement, query: String, placeholder: String,
                onQuery: @escaping @MainActor (String) -> Void, onMove: @escaping @MainActor (Int) -> Void,
                onReturn: @escaping @MainActor () -> Void, onClose: @escaping @MainActor () -> Void,
                @ViewBuilder content: () -> Content) {
        self.init(theme: theme, placement: placement, query: query, placeholder: placeholder, onQuery: onQuery,
                  onMove: onMove, onReturn: onReturn, onClose: onClose, hint: { EmptyView() }, content: content)
    }
}

/// Rows under one title, or under none (`title` nil: no header is drawn).
public struct KeyPanelGroup<Row: Identifiable>: Identifiable {
    public var id: String
    public var title: String?
    public var rows: [Row]

    public init(id: String = "", title: String? = nil, rows: [Row]) {
        self.id = id
        self.title = title
        self.rows = rows
    }
}

/// A key panel's rows: one scrolling column, the selected row lit and
/// scrolled into view, the row under the pointer lit less (`hoverFill`), a
/// click handed to `onClick`. The caller draws what is in a row (`row`, told
/// whether it is the selected one) and a group's title (`header`); the row's
/// height, inset, selection and hover are drawn here, so every Grove list of
/// this kind looks alike (the launcher, the cheat sheet, the key editor's
/// lists). Several lists side by side make columns: each scrolls on its own,
/// and a selection in another column moves nothing.
///
/// For VoiceOver a row is one button, selected or not, named by `label`
/// (else by the texts in it).
///
/// Not SwiftUI's `List(selection:)`, on purpose. A `List` moves its selection
/// only while it has the keyboard focus, and here the focus has to stay in
/// the field (one AppKit first responder, in a non-activating panel that may
/// not even be its app's key window), so ↑/↓ would have to be forwarded and
/// the selection set from outside anyway; and its selection is drawn in the
/// system's accent, not `bg2`. Whether a focusless `List` scrolls to and
/// draws a selection set that way can't be checked without running the
/// panel, so the rows stay hand-made, once, here.
public struct KeyPanelList<Row: Identifiable, Header: View, RowContent: View>: View where Row.ID: Sendable {
    let groups: [KeyPanelGroup<Row>]
    let selection: Row.ID?
    let position: Int?
    let rowHeight: CGFloat
    let rowSpacing: CGFloat
    let insets: EdgeInsets
    let label: ((Row) -> String)?
    let onClick: @MainActor (Row) -> Void
    let header: (String) -> Header
    let row: (Row, Bool) -> RowContent
    @Environment(\.theme) private var theme

    /// The selected row is scrolled into view when the selection changes.
    /// `position`: the selected row's place in the list, for a list that
    /// selects by place (the launcher: the first row of each new list): then
    /// the row is scrolled to when its place changes, instead. `rowSpacing`:
    /// a gap between rows (none in the panels). `label`: what VoiceOver
    /// calls a row.
    public init(_ groups: [KeyPanelGroup<Row>], selection: Row.ID?, position: Int? = nil,
                rowHeight: CGFloat, rowSpacing: CGFloat = 0, insets: EdgeInsets,
                label: ((Row) -> String)? = nil, onClick: @escaping @MainActor (Row) -> Void,
                @ViewBuilder header: @escaping (String) -> Header,
                @ViewBuilder row: @escaping (Row, Bool) -> RowContent) {
        self.groups = groups
        self.selection = selection
        self.position = position
        self.rowHeight = rowHeight
        self.rowSpacing = rowSpacing
        self.insets = insets
        self.label = label
        self.onClick = onClick
        self.header = header
        self.row = row
    }

    public var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: rowSpacing) {
                    ForEach(groups) { group in
                        if let title = group.title { header(title).accessibilityAddTraits(.isHeader) }
                        ForEach(group.rows) { item in
                            let selected = item.id == selection
                            KeyPanelRow(selected: selected, height: rowHeight, label: label?(item),
                                        onClick: { onClick(item) }) {
                                row(item, selected)
                            }
                            .id(item.id)
                        }
                    }
                }
                .padding(insets)
            }
            // A list that opens on a row further down (the key editor's, on
            // the current value) starts with it in view.
            .onAppear {
                if let selection { scroll.scrollTo(selection) }
            }
            // A row that isn't in this list (another column's) scrolls nothing.
            .onChange(of: position.map(AnyHashable.init) ?? selection.map(AnyHashable.init)) { _, _ in
                if let selection { scroll.scrollTo(selection) }
            }
        }
    }
}

extension KeyPanelList where Header == EmptyView {
    /// One list of rows, without titles.
    public init(_ rows: [Row], selection: Row.ID?, position: Int? = nil, rowHeight: CGFloat,
                rowSpacing: CGFloat = 0, insets: EdgeInsets, label: ((Row) -> String)? = nil,
                onClick: @escaping @MainActor (Row) -> Void,
                @ViewBuilder row: @escaping (Row, Bool) -> RowContent) {
        self.init([KeyPanelGroup(rows: rows)], selection: selection, position: position, rowHeight: rowHeight,
                  rowSpacing: rowSpacing, insets: insets, label: label, onClick: onClick,
                  header: { _ in EmptyView() }, row: row)
    }
}

/// One row of a `KeyPanelList`: its inset and height, lit when selected
/// (`selectedFill`, outlined in light) and, less, under the pointer.
private struct KeyPanelRow<Content: View>: View {
    let selected: Bool
    let height: CGFloat
    let label: String?
    let onClick: @MainActor () -> Void
    let content: Content
    @Environment(\.theme) private var theme
    /// `State` used directly: the Command Line Tools ship no SwiftUI macros.
    private var hovering = State(initialValue: false)

    init(selected: Bool, height: CGFloat, label: String?, onClick: @escaping @MainActor () -> Void,
         @ViewBuilder content: () -> Content) {
        self.selected = selected
        self.height = height
        self.label = label
        self.onClick = onClick
        self.content = content()
    }

    var body: some View {
        let fill = selected ? theme.selectedFill(on: .base)
            : (hovering.wrappedValue ? theme.hoverFill(on: .base) : Color.clear)
        let row = content
            .padding(.horizontal, GroveSpace.s8)
            .frame(height: height)
            .background(fill, in: RoundedRectangle(cornerRadius: GroveRadius.control))
            .lightOutline(cornerRadius: GroveRadius.control, when: selected)
            .contentShape(Rectangle())
            .onTapGesture { onClick() }
            .onHover { hovering.wrappedValue = $0 }
            // A trait, not a `Button`: a button would take the keyboard from the field.
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { onClick() }
        if let label { row.accessibilityLabel(label) } else { row }
    }
}
