import Foundation
import GroveThemesCore

/// The fixed data a render draws from, in place of `grove-themes`: the six
/// schemes read from the checkout's theme files, the scheme being rendered as
/// the current one, and both logos and wallpaper sets with `grove` chosen.
/// Nothing on this Mac is read but the checkout, and nothing is ever set.
enum RenderSamples {
    /// The colours `grove-themes list --json` carries for each scheme
    /// (`_gt_palette_json` in `grove-themes/bin/grove-themes`), in its order.
    static let colorNames = [
        "bg0", "bg1", "bg2", "bg3", "fg", "grey1", "red", "orange", "yellow", "green", "aqua", "blue", "purple",
        "border", "on_accent", "dim", "lockup_ink", "hover",
        "list_selected", "list_selected_inactive", "list_hover", "hidden_ink",
    ]

    /// The repository this executable was built in: the first folder up from
    /// the executable (then from the working directory) that holds
    /// `grove-dotfiles/theme`. Nil when there is none (an installed app).
    static func checkout(executable: URL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]),
                         workingDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        -> URL? {
        for start in [executable.resolvingSymlinksInPath().deletingLastPathComponent(), workingDirectory] {
            var folder = start.standardizedFileURL
            while folder.path != "/" {
                var isFolder: ObjCBool = false
                let theme = folder.appendingPathComponent("grove-dotfiles/theme").path
                if FileManager.default.fileExists(atPath: theme, isDirectory: &isFolder), isFolder.boolValue {
                    return folder
                }
                folder.deleteLastPathComponent()
            }
        }
        return nil
    }

    /// A theme file's `name = #RRGGBB` lines; nil if it can't be read.
    static func values(_ file: URL) -> [String: String]? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        var values: [String: String] = [:]
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 { values[parts[0]] = parts[1] }
        }
        return values
    }

    /// "dark-medium" → "Dark Medium", as the CLI titles a palette.
    static func title(_ scheme: String) -> String {
        scheme.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// The palette of the theme file at `file`, named `scheme`, as `list --json` has it.
    static func palette(_ scheme: String, file: URL) -> Palette? {
        guard let values = values(file) else { return nil }
        var colors: [String: String] = [:]
        for name in colorNames {
            guard let hex = values[name] else { return nil }
            colors[name] = hex
        }
        return Palette(name: title(scheme), appearance: scheme.hasPrefix("light") ? "light" : "dark", colors: colors)
    }

    /// The six schemes from `themes` (the checkout's `grove-dotfiles/theme`),
    /// plus `extra` (a theme file given by its path) when it isn't one of them,
    /// with `current` marked.
    static func list(themes: URL, current: String, extra: (name: String, file: URL)? = nil) -> SchemeList? {
        let names = ["dark-hard", "dark-medium", "dark-soft", "light-hard", "light-medium", "light-soft"]
        var palettes: [String: Palette] = [:]
        for name in names {
            guard let palette = palette(name, file: themes.appendingPathComponent("everforest-\(name)")) else {
                return nil
            }
            palettes[name] = palette
        }
        var schemes = names
        if let extra, palettes[extra.name] == nil {
            guard let palette = palette(extra.name, file: extra.file) else { return nil }
            palettes[extra.name] = palette
            schemes.append(extra.name)
        }
        guard palettes[current] != nil else { return nil }
        return SchemeList(current: current, schemes: schemes, palettes: palettes,
                          logo: "grove", logos: SchemeList.defaultLogos,
                          wallpaper: "grove", wallpapers: SchemeList.defaultWallpapers)
    }

    /// `list` as `grove-themes list --json` prints it.
    static func json(_ list: SchemeList) -> Data {
        var object: [String: Any] = [
            "current": list.current, "schemes": list.schemes,
            "logo": list.logo, "logos": list.logos,
            "wallpaper": list.wallpaper, "wallpapers": list.wallpapers,
        ]
        object["palettes"] = list.palettes.mapValues {
            ["name": $0.name, "appearance": $0.appearance, "colors": $0.colors] as [String: Any]
        }
        // Built from strings and arrays of them only, so it always encodes.
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }
}

/// `grove-themes` for a render: `list --json` answers with the sample list
/// and `log` with no switches (the model's `refresh` reads both). Anything
/// else throws, so a render can never switch a scheme, a logo or a wallpaper.
struct SampleRunner: CLIRunner {
    let list: Data

    init(list: SchemeList) {
        self.list = RenderSamples.json(list)
    }

    func run(_ arguments: [String]) async throws -> CLIOutput {
        switch arguments.first {
        case "list": return CLIOutput(status: 0, stdout: list, stderr: "")
        case "log": return CLIOutput(status: 0, stdout: Data(#"{"entries": []}"#.utf8), stderr: "")
        default: throw CLIError.unreadable("a render never runs grove-themes \(arguments.joined(separator: " "))")
        }
    }
}
