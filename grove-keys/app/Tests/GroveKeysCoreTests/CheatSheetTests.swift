import Foundation
import Testing
@testable import GroveKeysCore

@Suite struct CheatSheetTests {
    func shipped() throws -> KeysFile { try KeysFile(text: fixture("keys.toml")) }

    func sections(_ keys: KeysFile, ghostty: [CheatRow] = []) -> [CheatSection] {
        CheatSheet.sections(keys: keys, ghostty: ghostty) { $0 == "com.mitchellh.ghostty" ? "Ghostty" : nil }
    }

    @Test func theShippedFilesSections() throws {
        let all = sections(try shipped())
        #expect(all.map(\.id) == ["hyper", "mode:main", "mode:service", "shell", "macos"])
        #expect(all.map(\.title) == ["Hyper", "AeroSpace", "AeroSpace · Service mode", "Shell", "macOS"])
        #expect(all.map(\.fixed) == [false, false, false, true, true])

        // The comment says what a binding does; the command is there to find it by.
        let hyper = all[0].rows
        #expect(hyper.map(\.keys) == ["Hyper Space", "Hyper K"])
        #expect(hyper.map(\.text) == ["The Grove menu, type to filter", "Every key, searchable"])
        #expect(hyper[0].detail == "hyper-space exec-and-forget open grovekeys://palette")
        #expect(hyper[0].action == .run([.link(.palette)]))
        // The sheet's own key: Return only closes the sheet.
        #expect(hyper[1].action == .none)

        // Main has no Hyper rows, and each run of nine is one row.
        let main = all[1].rows
        #expect(main.count == 17)
        #expect(!main.contains { $0.keys.hasPrefix("Hyper") || $0.keys.contains("⌘") })
        #expect(main[2].id == "mode:main/alt-h")
        #expect(main[2].keys == "⌥ H" && main[2].text == "Focus left")
        #expect(main[2].action == .run([.aerospace(["focus", "left"])]))
        let workspaces = try #require(main.first { $0.keys == "⌥ 1 … 9" })
        #expect(workspaces.text == "Workspace 1 … 9")
        #expect(workspaces.action == .none)
        #expect(workspaces.detail.contains("alt-3"))
        #expect(main.first { $0.keys == "⌥⇧ 1 … 9" }?.text == "Move to workspace 1 … 9")
        #expect(main.last?.text == "Service mode")
        #expect(main.last?.action == .run([.aerospace(["mode", "service"])]))

        let service = all[2].rows
        #expect(service.map(\.text) == [
            "Reload config", "Reset the layout", "Float or tile the window", "Close the other windows",
            "Join with left", "Join with down", "Join with up", "Join with right",
        ])
        #expect(service[1].keys == "R")
        // Each command of a list is run, the way back to main too.
        #expect(service[1].action == .run([.aerospace(["flatten-workspace-tree"]), .aerospace(["mode", "main"])]))
        #expect(service[1].detail == "r flatten-workspace-tree, mode main")

        #expect(all[3].rows.map(\.keys) == ["⌃ R", "⌃ T", "⌥ C", "⌃ `"])
        #expect(all[4].rows.map(\.keys) == ["⇧⌘ 3", "⇧⌘ 4", "⇧⌘ 5", "⌃⌘ Space", "⌘ Space", "⌃⌘ Q", "Fn Fn"])
        #expect(all.flatMap(\.rows).filter { $0.id.hasPrefix("shell/") || $0.id.hasPrefix("macos/") }
            .allSatisfy { $0.action == .none })
        let ids = all.flatMap(\.rows).map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func launchersLeadTheHyperSection() throws {
        var keys = try shipped()
        keys.setLaunch(key: "t", bundleID: "com.mitchellh.ghostty")
        keys.setLaunch(key: "enter", bundleID: "com.example.Missing")
        // The launcher wins the key, as on the drawn keyboard.
        keys.setBinding(mode: "main", key: "cmd-ctrl-alt-shift-t", value: .string("workspace 3"))
        let hyper = sections(keys)[0].rows
        #expect(hyper.map(\.keys) == ["Hyper T", "Hyper ↩", "Hyper Space", "Hyper K"])
        #expect(hyper[0].text == "Ghostty")
        #expect(hyper[0].action == .launch(bundleID: "com.mitchellh.ghostty"))
        #expect(hyper[0].detail == "com.mitchellh.ghostty")
        #expect(hyper[1].text == "Missing (not installed)")
        #expect(hyper[1].action == .none)
        #expect(!sections(keys)[1].rows.contains { $0.detail.contains("workspace 3") })
    }

    @Test func modesKeepTheFilesOrderAndEmptySectionsGo() throws {
        let keys = try KeysFile(text: """
            [aerospace.resize]
            h = "resize width -50"
            [aerospace.main]
            alt-r = "mode resize"
            [aerospace.empty]
            """)
        let all = sections(keys, ghostty: [CheatRow(id: "ghostty/quit", keys: "⌘ Q", text: "Quit")])
        // No Hyper section; Ghostty comes last, under the two short lists.
        #expect(all.map(\.id) == ["mode:main", "mode:resize", "shell", "macos", "ghostty"])
        #expect(all[1].title == "AeroSpace · Resize mode")
        #expect(all[1].rows.map(\.text) == ["Shrink width by 50"])
        #expect(all[0].rows.map(\.text) == ["Resize mode"])
    }

    @Test func commandsInWords() {
        func w(_ command: String) -> String { CommandWords.words(command: command) }
        #expect(w("focus left") == "Focus left")
        #expect(w("move up") == "Move up")
        #expect(w("workspace 3") == "Workspace 3")
        #expect(w("move-node-to-workspace 4") == "Move to workspace 4")
        #expect(w("workspace-back-and-forth") == "Previous workspace")
        #expect(w("move-workspace-to-monitor --wrap-around next") == "Move workspace to the next monitor")
        #expect(w("layout tiles horizontal vertical") == "Tiles layout")
        #expect(w("layout accordion horizontal vertical") == "Accordion layout")
        #expect(w("layout floating tiling") == "Float or tile")
        #expect(w("resize smart -50") == "Shrink by 50")
        #expect(w("resize smart +50") == "Grow by 50")
        #expect(w("resize height +20") == "Grow height by 20")
        #expect(w("resize smart 50") == "Resize smart 50")
        #expect(w("mode service") == "Service mode")
        #expect(w("reload-config") == "Reload config")
        #expect(w("fullscreen") == "Fullscreen")
        #expect(w("exec-and-forget open grovekeys://palette") == "Grove menu palette")
        #expect(w("exec-and-forget open grovekeys://cheatsheet") == "Cheat sheet")
        // No words for these: as they are written.
        #expect(w("focus --boundaries all-monitors-outer-frame left") == "focus --boundaries all-monitors-outer-frame left")
        #expect(w("exec-and-forget open -a Safari") == "exec-and-forget open -a Safari")
        #expect(w("exec-and-forget open grovekeys://menu/learn") == "exec-and-forget open grovekeys://menu/learn")

        #expect(CommandWords.words(.array(["join-with right", "mode main"])) == "Join with right")
        #expect(CommandWords.words(.array(["mode main"])) == "Main mode")
        #expect(CommandWords.words(.array(["close", "fullscreen", "mode main"])) == "Close, Fullscreen")
    }

    @Test func whatReturnRuns() {
        #expect(CheatStep(command: "focus left") == .aerospace(["focus", "left"]))
        #expect(CheatStep(command: " resize  smart +50 ") == .aerospace(["resize", "smart", "+50"]))
        #expect(CheatStep(command: "exec-and-forget open grovekeys://palette") == .link(.palette))
        #expect(CheatStep(command: "exec-and-forget open -a 'Google Chrome'") == .shell("open -a 'Google Chrome'"))
        #expect(CheatStep(command: "exec-and-forget open grovekeys://nope") == .shell("open grovekeys://nope"))
        #expect(CheatStep(command: "exec-and-forget") == nil)
        #expect(CheatStep(command: "  ") == nil)

        // Whether the app in front before gets the keyboard back.
        #expect(!CheatAction.none.takesFocus)
        #expect(CheatAction.launch(bundleID: "a.b").takesFocus)
        #expect(!CheatAction.run([.aerospace(["focus", "left"]), .aerospace(["mode", "main"])]).takesFocus)
        #expect(!CheatAction.run([.shell("say hi")]).takesFocus)
        #expect(CheatAction.run([.link(.palette)]).takesFocus)
    }

    @Test func theFilterKeepsTheRowsWithEveryWord() throws {
        let all = sections(try shipped(), ghostty: GhosttyKeybinds.rows(listing: try fixture("ghostty-keybinds.txt")))
        #expect(CheatSheet.filter(all, "") == all)
        #expect(CheatSheet.filter(all, "  ") == all)
        #expect(CheatSheet.filter(all, "zzz").isEmpty)
        func found(_ query: String) -> [String] { CheatSheet.filter(all, query).flatMap(\.rows).map(\.id) }
        // The text, whatever the case; sections without a match are gone.
        let focus = CheatSheet.filter(all, "FOCUS le")
        #expect(focus.map(\.id) == ["mode:main"])
        #expect(focus[0].rows.map(\.keys) == ["⌥ H"])
        // The key as it is shown, and as the file writes it.
        #expect(found("⌥⇧ ;") == ["mode:main/alt-shift-semicolon"])
        #expect(found("alt-shift-semicolon") == ["mode:main/alt-shift-semicolon"])
        // The command behind a comment.
        #expect(found("flatten") == ["mode:service/r"])
        // A section's name brings all its rows, and narrows with more words.
        #expect(CheatSheet.filter(all, "shell").map(\.id) == ["shell"])
        #expect(found("shell").count == 4)
        #expect(found("macos lock") == ["macos/lock"])
        #expect(found("service join right") == ["mode:service/alt-shift-l"])
        // Across sections, in the sheet's order.
        #expect(found("quick terminal") == ["shell/quick", "ghostty/toggle_quick_terminal"])
    }
}

@Suite struct GhosttyKeybindsTests {
    /// The fixture is what Ghostty 1.4.0 printed on the owner's Mac.
    @Test func aReadableSubsetOfTheRealListing() throws {
        let listing = try fixture("ghostty-keybinds.txt")
        #expect(listing.split(separator: "\n").count == 94)
        let rows = GhosttyKeybinds.rows(listing: listing)
        func row(_ action: String) -> CheatRow? { rows.first { $0.id == "ghostty/" + action } }
        #expect(rows.count == 56)
        #expect(rows.allSatisfy { $0.action == .none })
        #expect(Set(rows.map(\.id)).count == rows.count)

        #expect(rows.first?.keys == "⇧⌘ ," && rows.first?.text == "Reload config")
        #expect(row("new_split:down")?.keys == "⇧⌘ D")
        #expect(row("new_split:down")?.text == "New split: down")
        #expect(row("resize_split:up,10")?.keys == "⌃⌘ ↑")
        #expect(row("resize_split:up,10")?.text == "Resize split: up, 10")
        #expect(row("goto_split:previous")?.keys == "⌘ [")
        #expect(row("goto_split:previous")?.text == "Go to split: previous")
        #expect(row("toggle_quick_terminal")?.keys == "⌃ `")
        #expect(row("scroll_page_up")?.keys == "⌘ Page Up")
        // The key can be = itself; ⌘ + is its twin and isn't listed again.
        #expect(row("increase_font_size:1")?.keys == "⌘ =")
        // One row per action, under the key with the fewest modifiers.
        #expect(row("undo")?.keys == "⌘ Z")
        #expect(row("toggle_fullscreen")?.keys == "⌘ ↩")
        #expect(row("next_tab")?.keys == "⌃ ⇥")
        #expect(row("jump_to_prompt:-1")?.keys == "⌘ ↑")
        // ⌘ 1 … 8 are one row; the digit_N twins are not listed.
        #expect(row("goto_tab")?.keys == "⌘ 1 … 8")
        #expect(row("goto_tab")?.text == "Go to tab: 1 … 8")
        #expect(!rows.contains { $0.id.hasPrefix("ghostty/goto_tab:") || $0.keys.contains("digit") })
        #expect(row("last_tab")?.keys == "⌘ 9")
        // No ⌃, ⌥ or ⌘: not listed. Nor the keys that send bytes.
        #expect(!rows.contains { $0.detail.hasPrefix("adjust_selection") || $0.detail == "end_search" && $0.keys == "Esc" })
        #expect(row("end_search")?.keys == "⇧⌘ F")
        #expect(!rows.contains { $0.detail.hasPrefix("text:") || $0.detail.hasPrefix("esc:") })
    }

    @Test func oddLines() {
        let rows = GhosttyKeybinds.rows(listing: """
            warning: something on stderr
            keybind = global:ctrl+grave_accent=toggle_quick_terminal
            keybind = ctrl+a>n=new_window
            keybind = super++=increase_font_size:2
            keybind = hyper+x=quit
            keybind = super+1=goto_tab:1
            keybind = super+2=goto_tab:2
            keybind = super+u=unbind
            keybind = super+broken
            """)
        #expect(rows.map(\.keys) == ["⌃ `", "⌘ +", "⌘ 1", "⌘ 2"])
        #expect(rows.map(\.text) == ["Toggle quick terminal", "Increase font size: 2", "Go to tab: 1", "Go to tab: 2"])
        #expect(GhosttyKeybinds.rows(listing: "").isEmpty)
    }
}
