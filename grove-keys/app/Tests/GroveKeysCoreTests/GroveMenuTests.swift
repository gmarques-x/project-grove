import Foundation
import Testing
@testable import GroveKeysCore

@Suite struct GroveMenuTests {
    private let home = URL(fileURLWithPath: "/Users/test")

    @Test func readsTheShippedFileInFileOrder() throws {
        let menu = try GroveMenu.strict(main: try fixture("menu.toml"))
        #expect(menu.rows.map(\.id) == ["appearance", "keys", "update", "learn", "about", "system", "global-menu"])
        #expect(menu.rows.map(\.title) == ["Appearance", "Grove Keys", "Update", "Learn", "About", "System", "Global Menu"])
        #expect(menu.count == 29)

        let appearance = menu.rows[0]
        #expect(appearance.action == nil)
        #expect(appearance.children.map(\.id) == [
            "appearance.gallery", "appearance.dark-hard", "appearance.dark-medium", "appearance.dark-soft",
            "appearance.light-hard", "appearance.light-medium", "appearance.light-soft",
        ])
        #expect(appearance.children[0].action == .open("grovethemes://gallery"))
        let hard = appearance.children[1]
        #expect(hard.title == "Dark Hard" && hard.separator)
        #expect(hard.action == .run("grove-themes set dark-hard"))
        #expect(hard.checked == #"test "$(grove-themes current)" = dark-hard"#)

        #expect(menu.rows[1].action == .builtin(.keys))
        #expect(menu.row(id: "update.check")?.action == .present("grove check"))
        #expect(menu.row(id: "system.lock")?.action == .builtin(.lock))
        // System Settings leads the System submenu, set apart from Lock and the rest.
        #expect(menu.row(id: "system")?.children.first?.id == "system.settings")
        #expect(menu.row(id: "system.settings")?.action == .open("/System/Applications/System Settings.app"))
        #expect(menu.row(id: "system.settings")?.action?.takesFocus == true)
        #expect(OpenTarget("/System/Applications/System Settings.app", home: home)
            == .url(URL(fileURLWithPath: "/System/Applications/System Settings.app")))
        #expect(menu.row(id: "system.lock")?.separator == true)
        #expect(menu.row(id: "system.logout")?.action
            == .run(#"osascript -e 'tell application "loginwindow" to «event aevtrlgo»'"#))
        let global = try #require(menu.rows.last)
        #expect(global.action == .builtin(.globalMenu) && global.separator)
    }

    @Test func theShippedTopLevelRowsEachHaveAnIcon() throws {
        let menu = try GroveMenu.strict(main: try fixture("menu.toml"))
        #expect(menu.rows.map(\.icon) == ["paintpalette", "keyboard", "arrow.triangle.2.circlepath", "book",
                                          "info.circle", "power", "menubar.rectangle"])
        // Only the top level: the names are held to Grove's icons by `--check-menu`.
        #expect(menu.icons.map(\.id) == menu.rows.map(\.id))
        #expect(menu.icons.map(\.icon) == menu.rows.compactMap(\.icon))
        // The Grove Keys row keeps its icon when its items take the builtin's place.
        let keys = KeysMenuItem.items(accessibility: true, inputMonitoring: true, redLine: nil, offersRestart: false,
                                      paused: false)
        #expect(menu.expandingKeys(keys).row(id: "keys")?.icon == "keyboard")
        #expect(menu.expandingKeys(keys).row(id: "keys.pause")?.icon == nil)
    }

    @Test func anIconIsARowsKeyAndTheLocalFileSetsChangesOrRemovesIt() throws {
        let main = """
            [a]
            title = "A"
            icon = "book"
            [a.one]
            run = "x"
            icon = "wifi"
            [b]
            run = "b"
            icon = "power"
            [c]
            run = "c"
            """
        let menu = try GroveMenu.strict(main: main)
        #expect(menu.rows.map(\.icon) == ["book", "power", nil])
        // A submenu's row keeps an icon the file gives it (the pine's menu draws the top level's only).
        #expect(menu.row(id: "a.one")?.icon == "wifi")
        #expect(menu.icons.map(\.id) == ["a", "a.one", "b"])

        let local = "[a]\nicon = \"keyboard\"\n[b]\nicon = \"\"\n[c]\nicon = \"calendar\"\n[d]\nrun = \"d\"\nicon = \"not.a.symbol\"\n"
        let merged = try GroveMenu.strict(main: main, local: local)
        // The name is kept as written: whether Grove has that icon is the app's to say.
        #expect(merged.rows.map(\.icon) == ["keyboard", nil, "calendar", "not.a.symbol"])
        #expect(merged.row(id: "a")?.title == "A")
    }

    @Test func anIconMustBeAString() {
        #expect(throws: MenuFileError(file: "menu.toml", line: 3, message: #""icon" must be a string"#)) {
            try GroveMenu.strict(main: "[a]\nrun = \"x\"\nicon = true\n")
        }
    }

    @Test func thePathToARowIsItsParentsThenItself() throws {
        let menu = try GroveMenu.strict(main: "[a]\ntitle = \"A\"\n[a.b]\ntitle = \"B\"\n[a.b.c]\nrun = \"c\"\n[d]\nrun = \"d\"\n")
        #expect(menu.path(to: "a.b.c") == ["a", "a.b", "a.b.c"])
        #expect(menu.path(to: "a.b") == ["a", "a.b"])
        #expect(menu.path(to: "d") == ["d"])
        #expect(menu.path(to: "nope").isEmpty && menu.path(to: "").isEmpty)
    }

    @Test func aRowWithRowsUnderItIsASubmenuAndOneWithNothingIsLeftOut() throws {
        let menu = try GroveMenu.strict(main: """
        [tools]
        title = "Tools"
        run = "ignored"
        checked = "true"
        [tools.one]
        run = "one"
        [empty]
        title = "Empty"
        [deep.er.leaf]
        title = "Leaf"
        open = "~/x"
        [hollow]
        title = "Hollow"
        [hollow.inside]
        title = "No action"
        """)
        #expect(menu.rows.map(\.id) == ["tools", "deep"])
        #expect(menu.rows[0].action == nil && menu.rows[0].checked == nil)
        // No title: the last part of the id; so are parents no table names.
        #expect(menu.rows[0].children.map(\.title) == ["one"])
        #expect(menu.rows[1].title == "deep")
        #expect(menu.rows[1].children[0].children[0].id == "deep.er.leaf")
        #expect(menu.count == 5)
    }

    @Test func aParentNamedAfterItsRowsKeepsItsFirstPlace() throws {
        let menu = try GroveMenu.strict(main: """
        [a.x]
        run = "x"
        [b]
        run = "b"
        [a]
        title = "A"
        """)
        #expect(menu.rows.map(\.title) == ["A", "b"])
    }

    @Test func theLocalFileChangesAddsAndHidesRows() throws {
        let menu = try GroveMenu.strict(main: try fixture("menu.toml"), local: """
        [update.check]
        title = "Check Now"
        [about]
        run = "say hi"
        separator = true
        [learn.yazi]
        hidden = true
        [system]
        hidden = true
        [learn.mine]
        title = "Mine"
        open = "~/notes.md"
        [work.vpn.on]
        title = "On"
        run = "vpn on"
        """)
        let check = try #require(menu.row(id: "update.check"))
        #expect(check.title == "Check Now" && check.action == .present("grove check"))
        let about = try #require(menu.row(id: "about"))
        #expect(about.title == "About" && about.action == .run("say hi") && about.separator)
        #expect(menu.row(id: "learn.yazi") == nil)
        #expect(menu.row(id: "system") == nil && menu.row(id: "system.lock") == nil)
        #expect(menu.row(id: "learn")?.children.last?.id == "learn.mine")
        // New top rows go last; missing parents are made, named by their id.
        #expect(menu.rows.map(\.id) == ["appearance", "keys", "update", "learn", "about", "global-menu", "work"])
        let work = try #require(menu.rows.last)
        #expect(work.title == "work" && work.children[0].title == "vpn")
        #expect(work.children[0].children[0].action == .run("vpn on"))
    }

    @Test func theLocalFileCanShowAHiddenRowAgain() throws {
        let menu = try GroveMenu.strict(main: "[a]\nrun = \"a\"\nhidden = true\n", local: "[a]\nhidden = false\n")
        #expect(menu.rows.map(\.id) == ["a"])
    }

    @Test(arguments: [
        ("[a]\ntitle = \"A\"\nrun = \"x\"\nopen = \"y\"\n", 4, #"one action: "run" is already set"#),
        ("[a]\nbuiltin = \"nope\"\n", 2, #"unknown builtin "nope""#),
        ("[a]\ntitel = \"A\"\n", 2, #"unknown key "titel""#),
        ("[a]\ntitle = 3\n", 2, #""title" must be a string"#),
        ("[a]\ntitle = \"\"\n", 2, #""title" must be a string"#),
        ("[a]\nrun = \"x\"\nhidden = \"yes\"\n", 3, #""hidden" must be true or false"#),
        ("[a]\nrun = [\"x\"]\n", 2, #""run" must be a string"#),
        ("title = \"A\"\n", 1, #""title" is outside a table"#),
        ("[a]\nrun = \"x\n", 2, "unterminated string"),
    ])
    func errorsNameTheFileAndLine(text: String, line: Int, message: String) {
        do {
            _ = try GroveMenu.strict(main: text)
            Issue.record("expected an error for \(text.debugDescription)")
        } catch {
            #expect(error.file == "menu.toml" && error.line == line)
            #expect(error.message.contains(message), "got: \(error.message)")
            #expect(error.description.hasPrefix("menu.toml line \(line): "))
        }
        do {
            _ = try GroveMenu.strict(main: "[ok]\nrun = \"x\"\n", local: text)
            Issue.record("expected an error for the local \(text.debugDescription)")
        } catch {
            #expect(error.file == "menu.local.toml" && error.line == line)
        }
    }

    @Test func aBrokenTrackedFileGivesTheBuiltInMenuWithTheErrorFirst() {
        let menu = GroveMenu.load(main: .success("[a]\nrun = \n"), local: .success("[b]\nrun = \"b\"\n"))
        #expect(menu.rows.map(\.title) == ["menu.toml line 2: missing value after =", "Grove Themes", "Grove Keys", "Global Menu"])
        #expect(menu.rows[0].isNote && menu.rows[1].separator)
        #expect(menu.rows.dropFirst().map(\.action) == [.open("grovethemes://gallery"), .builtin(.keys), .builtin(.globalMenu)])

        let unread = GroveMenu.load(
            main: .failure(MenuFileError(file: "menu.toml", line: 0, message: "can't be read")), local: nil)
        #expect(unread.rows[0].title == "menu.toml: can't be read")
        #expect(unread.rows.count == 4)
    }

    @Test func aBrokenLocalFileIsLeftOutWithTheErrorFirst() {
        let main = "[a]\nrun = \"a\"\n[b]\nrun = \"b\"\n"
        let menu = GroveMenu.load(main: .success(main), local: .success("[a]\nhidden = true\n[c]\nrun = 1\n"))
        #expect(menu.rows.map(\.title) == [#"menu.local.toml line 4: "run" must be a string"#, "a", "b"])
        #expect(menu.rows[0].isNote && menu.rows[1].separator)
        #expect(menu.count == 2)
        #expect(GroveMenu.load(main: .success(main), local: nil).rows.map(\.id) == ["a", "b"])
    }

    @Test func readsTheFilesAndToleratesAMissingLocalOne() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("grove-menu-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let paths = MenuPaths(main: dir.appendingPathComponent("menu.toml"), local: dir.appendingPathComponent("menu.local.toml"))
        #expect(GroveMenu.read(paths).rows.first?.title == "menu.toml: can't be read")
        try "[a]\nrun = \"a\"\n".write(to: paths.main, atomically: true, encoding: .utf8)
        #expect(GroveMenu.read(paths).rows.map(\.id) == ["a"])
        try "[b]\nrun = \"b\"\n".write(to: paths.local, atomically: true, encoding: .utf8)
        #expect(GroveMenu.read(paths).rows.map(\.id) == ["a", "b"])
    }

    @Test func menuPathsFollowTheConfigFolder() {
        let paths = MenuPaths.standard(home: home, environment: [:])
        #expect(paths.main.path == "/Users/test/.config/grove/menu.toml")
        #expect(paths.local.path == "/Users/test/.config/grove/menu.local.toml")
        #expect(MenuPaths.standard(home: home, environment: ["XDG_CONFIG_HOME": "/x"]).main.path == "/x/grove/menu.toml")
    }

    @Test func findsRowsById() throws {
        let menu = try GroveMenu.strict(main: try fixture("menu.toml"))
        #expect(menu.row(id: "learn")?.children.count == 5)
        #expect(menu.row(id: "appearance.dark-medium")?.title == "Dark Medium")
        #expect(menu.row(id: "global-menu")?.action == .builtin(.globalMenu))
        #expect(menu.row(id: "nope") == nil && menu.row(id: "") == nil)
    }

    // MARK: Grove Keys' own items

    @Test func theKeysItemsAreAsTheMenuAlwaysHadThem() {
        let calm = KeysMenuItem.items(accessibility: true, inputMonitoring: true, redLine: nil, offersRestart: false, paused: false)
        #expect(calm.map(\.title) == ["Open Grove Keys", "Show cheat sheet", "Pause Hyper"])
        #expect(calm.allSatisfy { !$0.separator })

        let trouble = KeysMenuItem.items(accessibility: false, inputMonitoring: false, redLine: "keys.toml line 3: bad",
                                         offersRestart: true, paused: true)
        #expect(trouble.map(\.kind) == [.accessibility, .inputMonitoring, nil, .restart, .open, .cheatSheet, .pause])
        #expect(trouble.map(\.title) == [
            "Grove Keys needs Accessibility — Open Settings", "Grove Keys needs Input Monitoring — Open Settings",
            "keys.toml line 3: bad", "Restart Grove Keys", "Open Grove Keys", "Show cheat sheet", "Resume Hyper",
        ])
        #expect(trouble.map(\.separator) == [false, false, false, false, true, false, false])

        // A red line alone (a keys.toml error): no Restart, still set off by a line.
        let red = KeysMenuItem.items(accessibility: true, inputMonitoring: true, redLine: "bad", offersRestart: false, paused: false)
        #expect(red.map(\.kind) == [nil, .open, .cheatSheet, .pause] && red[1].separator)
    }

    @Test func expandingKeysMakesTheBuiltinAnOrdinarySubmenu() throws {
        let items = KeysMenuItem.items(accessibility: true, inputMonitoring: true, redLine: "bad", offersRestart: false, paused: false)
        let menu = try GroveMenu.strict(main: try fixture("menu.toml")).expandingKeys(items)
        let keys = try #require(menu.row(id: "keys"))
        #expect(keys.action == nil && keys.title == "Grove Keys")
        #expect(keys.children.map(\.id) == ["", "keys.open", "keys.cheatsheet", "keys.pause"])
        #expect(keys.children[0].isNote)
        #expect(menu.row(id: "keys.pause")?.action == .keys(.pause))
        #expect(menu.row(id: "global-menu")?.action == .builtin(.globalMenu))
    }

    // MARK: Running

    @Test func shellCommandsForRunAndPresent() {
        #expect(GroveMenuAction.run("a && b").shellCommand(title: "T") == "a && b")
        #expect(GroveMenuAction.present("grove check").shellCommand(title: "Check")
            == "grove present --title 'Check' grove check")
        #expect(GroveMenuAction.present("x").shellCommand(title: "It's $HOME") == #"grove present --title 'It'\''s $HOME' x"#)
        #expect(GroveMenuAction.open("x").shellCommand(title: "T") == nil)
        #expect(GroveMenuAction.builtin(.lock).shellCommand(title: "T") == nil)
    }

    @Test func rowsThatBringAWindowForwardTakeFocus() {
        #expect(!GroveMenuAction.run("x").takesFocus)
        #expect(!GroveMenuAction.builtin(.lock).takesFocus)
        #expect(GroveMenuAction.present("x").takesFocus)
        #expect(GroveMenuAction.open("https://ghostty.org/docs").takesFocus)
        #expect(GroveMenuAction.open("~/notes.md").takesFocus)
        // The cheat sheet has a field to type in, as the launcher.
        #expect(GroveMenuAction.open("grovekeys://cheatsheet").takesFocus)
        #expect(GroveMenuAction.keys(.open).takesFocus)
        #expect(GroveMenuAction.keys(.restart).takesFocus)
        #expect(GroveMenuAction.keys(.cheatSheet).takesFocus)
        #expect(!GroveMenuAction.keys(.pause).takesFocus)
    }

    @Test func openTargetsAreLinksOrPaths() throws {
        #expect(OpenTarget("grovekeys://cheatsheet", home: home) == .link(.cheatSheet))
        #expect(OpenTarget("grovekeys://menu/learn", home: home) == .link(.row(id: "learn")))
        #expect(OpenTarget("grovethemes://gallery", home: home) == .url(try #require(URL(string: "grovethemes://gallery"))))
        #expect(OpenTarget("https://ghostty.org/docs", home: home) == .url(try #require(URL(string: "https://ghostty.org/docs"))))
        #expect(OpenTarget("~/Documents/a b.md", home: home) == .url(URL(fileURLWithPath: "/Users/test/Documents/a b.md")))
        #expect(OpenTarget("~", home: home) == .url(home))
        #expect(OpenTarget("/Applications/Safari.app", home: home) == .url(URL(fileURLWithPath: "/Applications/Safari.app")))
        #expect(OpenTarget("notes/x.md", home: home) == .url(URL(fileURLWithPath: "/Users/test/notes/x.md")))
        #expect(OpenTarget("  ", home: home) == nil)
    }

    @Test func theShellEnvironmentHasGroveStateAndThePaths() {
        let bare = MenuShell.environment(from: ["PATH": "/usr/bin:/bin", "LANG": "C"], home: home)
        #expect(bare["GROVE_STATE"] == "/Users/test/.local/state/grove")
        #expect(bare["PATH"] == "/Users/test/.local/bin:/opt/homebrew/bin:/usr/bin:/bin")
        #expect(bare["LANG"] == "C")

        let set = MenuShell.environment(
            from: ["PATH": "/opt/homebrew/bin:/usr/bin", "GROVE_STATE": "/tmp/state"], home: home)
        #expect(set["GROVE_STATE"] == "/tmp/state")
        #expect(set["PATH"] == "/Users/test/.local/bin:/opt/homebrew/bin:/usr/bin")

        #expect(MenuShell.environment(from: [:], home: home)["PATH"]
            == "/Users/test/.local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin")
    }

    // MARK: The launcher

    private func shippedEntries() throws -> [LauncherEntry] {
        let items = KeysMenuItem.items(accessibility: true, inputMonitoring: true, redLine: "bad", offersRestart: false, paused: false)
        return try GroveMenu.strict(main: try fixture("menu.toml")).expandingKeys(items).launcherEntries
    }

    @Test func theLauncherListsEveryLeafByItsPath() throws {
        let entries = try shippedEntries()
        #expect(entries.count == 26)
        #expect(entries.prefix(3).map(\.text) == ["Appearance › Grove Themes…", "Appearance › Dark Hard", "Appearance › Dark Medium"])
        #expect(entries[1].id == "appearance.dark-hard" && entries[1].checked != nil)
        // Grove Keys' items are there (not its red line); the Global Menu is not.
        #expect(entries.filter { $0.path.first == "Grove Keys" }.map(\.title) == ["Open Grove Keys", "Show cheat sheet", "Pause Hyper"])
        #expect(!entries.contains { $0.text.contains("Global Menu") })
        #expect(entries.last?.text == "System › Shut Down…")
        #expect(entries.first { $0.id == "about" }?.path == ["About"])

        // A keys builtin that wasn't expanded has nothing to list.
        let plain = try GroveMenu.strict(main: try fixture("menu.toml")).launcherEntries
        #expect(plain.count == 23 && !plain.contains { $0.id == "keys" })
    }

    private func ids(_ rows: [LauncherEntry], apps: [InstalledApps.App] = [], _ query: String) -> [String] {
        LauncherFilter.filter(rows: rows, apps: apps, query).map(\.id)
    }

    @Test func theFilterWantsEveryWordAndPutsNameStartsFirst() throws {
        let entries = try shippedEntries()
        #expect(LauncherFilter.filter(rows: entries, apps: [], "") == entries.map(LauncherItem.row))
        #expect(LauncherFilter.filter(rows: entries, apps: [], "   ") == entries.map(LauncherItem.row))
        #expect(ids(entries, "DARK med") == ["row:appearance.dark-medium"])
        #expect(ids(entries, "soft appear") == ["row:appearance.dark-soft", "row:appearance.light-soft"])
        #expect(ids(entries, "zzz").isEmpty)
        // Both start with it: the shorter title first.
        #expect(LauncherFilter.filter(rows: entries, apps: [], "sh").prefix(2).map(\.name) == ["Shut Down…", "Show cheat sheet"])
        // "up": Update Grove (a title start) comes before the Update rows that
        // only have it in their path, though those are earlier in the menu.
        #expect(ids(entries, "up") == ["row:update.grove", "row:update.check", "row:update.install"])
        // The whole text is the prefix, spaces and all.
        #expect(ids(entries, "light s").first == "row:appearance.light-soft")
    }

    private func app(_ name: String) -> InstalledApps.App {
        InstalledApps.App(name: name, bundleID: "test." + name, path: "/Applications/\(name).app")
    }

    @Test func nothingTypedIsTheGroveMenuWithoutApps() throws {
        let entries = try shippedEntries()
        let all = LauncherFilter.filter(rows: entries, apps: [app("Safari"), app("Notes")], "")
        #expect(all == entries.map(LauncherItem.row))
    }

    @Test func typingRanksAppsAndRowsTogether() throws {
        let entries = try shippedEntries()
        let apps = ["App Store", "Google Chrome", "Safari", "Settings Helper", "System Settings", "Visual Studio Code",
                    "Shortcuts", "Ghostty"].map(app)
        func names(_ query: String) -> [String] {
            LauncherFilter.filter(rows: entries, apps: apps, query).map(\.name)
        }
        // A name that starts with it, apps before rows, shorter first.
        #expect(names("sa") == ["Safari"])
        #expect(names("s").prefix(5) == ["Safari", "Shortcuts", "Settings Helper", "System Settings", "Sleep"])
        // A word of the name starts with it: after the name starts, before a mere substring.
        #expect(names("chr") == ["Google Chrome"])
        #expect(names("stu") == ["Visual Studio Code"])
        #expect(names("sto") == ["App Store"])
        #expect(names("code") == ["Visual Studio Code"])
        // Each typed word starts a word: "vs c" doesn't, "vis co" does.
        #expect(names("vis co") == ["Visual Studio Code"])
        // An app and a Grove menu row of the same name: the app first.
        #expect(names("system settings") == ["System Settings", "System Settings…"])
        // Rows still match by their whole path, after the names that start with it.
        #expect(names("system").prefix(1) == ["System Settings"])
        #expect(names("system").contains("Lock"))
        // Accents and case don't matter; the app before the Learn row of the same name.
        #expect(LauncherFilter.filter(rows: entries, apps: apps, "GHÖ").map(\.id) == ["app:test.Ghostty", "row:learn.ghostty"])
        #expect(LauncherFilter.filter(rows: entries, apps: apps, "ghost").first?.id == "app:test.Ghostty")
    }
}
