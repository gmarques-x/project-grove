/// The AeroSpace commands the key editor offers (spec §7); anything else is
/// typed as free text.
public enum CommandCatalog {
    public static let entries: [(title: String, template: String)] = [
        ("workspace", "workspace N"),
        ("move-node-to-workspace", "move-node-to-workspace N"),
        ("focus left", "focus left"),
        ("focus down", "focus down"),
        ("focus up", "focus up"),
        ("focus right", "focus right"),
        ("move left", "move left"),
        ("move down", "move down"),
        ("move up", "move up"),
        ("move right", "move right"),
        ("resize −", "resize smart -50"),
        ("resize +", "resize smart +50"),
        ("layout tiles", "layout tiles horizontal vertical"),
        ("layout accordion", "layout accordion horizontal vertical"),
        ("float / tile", "layout floating tiling"),
        ("workspace back and forth", "workspace-back-and-forth"),
        ("workspace to next monitor", "move-workspace-to-monitor --wrap-around next"),
        ("service mode", "mode service"),
        ("close", "close"),
        ("reload-config", "reload-config"),
        ("fullscreen", "fullscreen"),
    ]

    /// The template with N as the key's digit (1 for any other key).
    public static func command(template: String, key: String) -> String {
        guard template.hasSuffix(" N") else { return template }
        let n = key.count == 1 && key.first!.isNumber ? key : "1"
        return String(template.dropLast()) + n
    }
}
