/// What one key does in one layer, as the Keyboard tab's editor sets it.
public enum KeyAction: Equatable, Sendable {
    case launcher(bundleID: String)
    case aerospace(command: String)
    case none
}

extension KeysFile {
    /// The key text an existing binding in `mode` uses for this shortcut
    /// ("hyper-t" may be written "cmd-ctrl-alt-shift-t"), else nil.
    func entryKey(mode: String, shortcut: String) -> String? {
        let wanted = Shortcut(aerospace: shortcut)
        let bindings = modes.first { $0.name == mode }?.bindings ?? []
        return bindings.first { $0.key == shortcut || (wanted != nil && Shortcut(aerospace: $0.key) == wanted) }?.key
    }

    private func launcherKey(layerID: String, shortcut: String) -> String? {
        guard layerID == "hyper", let sc = Shortcut(aerospace: shortcut), sc.isHyper else { return nil }
        return sc.key
    }

    private func value(mode: String, key: String) -> TomlValue? {
        modes.first { $0.name == mode }?.bindings.first { $0.key == key }?.value
    }

    /// `shortcut` is the AeroSpace key text in the layer's mode: "alt-1",
    /// "hyper-t", or in a mode "r" / "alt-shift-h". A launcher wins, as in Layers.
    public func action(layerID: String, shortcut: String) -> KeyAction {
        if let key = launcherKey(layerID: layerID, shortcut: shortcut),
           let id = launch.first(where: { $0.key == key })?.bundleID {
            return .launcher(bundleID: id)
        }
        return aerospaceAction(layerID: layerID, shortcut: shortcut) ?? .none
    }

    private func aerospaceAction(layerID: String, shortcut: String) -> KeyAction? {
        let mode = KeyboardLayout.mode(layerID: layerID)
        guard let key = entryKey(mode: mode, shortcut: shortcut), let v = value(mode: mode, key: key) else { return nil }
        switch v {
        case .string(let s): return .aerospace(command: s)
        case .array(let items):
            return .aerospace(command: items.first { $0.trimmingCharacters(in: .whitespaces) != "mode main" } ?? items.first ?? "")
        case .int(let n): return .aerospace(command: String(n))
        case .bool(let b): return .aerospace(command: String(b))
        }
    }

    /// On a Hyper key, what `assign` would remove: the `hyper-` binding when
    /// a launcher is chosen, the launcher when an AeroSpace command is. Nil
    /// when there is nothing of the other kind (and outside Hyper).
    public func replaced(byLauncher: Bool, layerID: String, shortcut: String) -> KeyAction? {
        guard let key = launcherKey(layerID: layerID, shortcut: shortcut) else { return nil }
        if byLauncher { return aerospaceAction(layerID: layerID, shortcut: shortcut) }
        return launch.first { $0.key == key }.map { .launcher(bundleID: $0.bundleID) }
    }

    /// The keys.toml line the key's action is saved as, for the editor's footer.
    public func savedLine(layerID: String, shortcut: String) -> String? {
        if let key = launcherKey(layerID: layerID, shortcut: shortcut),
           let id = launch.first(where: { $0.key == key })?.bundleID {
            return TomlDocument.keyText(key) + " = " + TomlDocument.valueText(.string(id))
        }
        let mode = KeyboardLayout.mode(layerID: layerID)
        guard let key = entryKey(mode: mode, shortcut: shortcut), let v = value(mode: mode, key: key) else { return nil }
        return TomlDocument.keyText(key) + " = " + TomlDocument.valueText(v)
    }

    /// False when an AeroSpace command can't go on this key: a main-mode
    /// binding without ⌃, ⌥ or ⌘ (the same rule as the Bindings tab, see
    /// `BindingSlot.isSafe`). Launchers and None are always allowed.
    public static func canAssignCommand(layerID: String, shortcut: String) -> Bool {
        BindingSlot.binding(mode: KeyboardLayout.mode(layerID: layerID), key: shortcut).isSafe
    }

    /// Sets what the key does; it does one thing, so a launcher replaces a
    /// `hyper-` binding on the same key and the other way round. A launcher
    /// outside the Hyper layer and a blank command change nothing. In a mode
    /// other than main a command is followed by "mode main", as the shipped
    /// service bindings are, unless it switches mode itself or the key was a
    /// plain string before. A command on a key `canAssignCommand` refuses
    /// changes nothing.
    public mutating func assign(_ action: KeyAction, layerID: String, shortcut: String) {
        let mode = KeyboardLayout.mode(layerID: layerID)
        let existing = entryKey(mode: mode, shortcut: shortcut)
        let launcher = launcherKey(layerID: layerID, shortcut: shortcut)
        switch action {
        case .none:
            if let launcher { removeLaunch(key: launcher) }
            if let existing { removeBinding(mode: mode, key: existing) }
        case .launcher(let id):
            guard let launcher else { return }
            setLaunch(key: launcher, bundleID: id)
            if let existing { removeBinding(mode: mode, key: existing) }
        case .aerospace(let raw):
            let command = raw.trimmingCharacters(in: .whitespaces)
            guard !command.isEmpty, Self.canAssignCommand(layerID: layerID, shortcut: shortcut) else { return }
            if let launcher { removeLaunch(key: launcher) }
            let old = existing.flatMap { value(mode: mode, key: $0) }
            let wasString: Bool
            if case .string = old { wasString = true } else { wasString = false }
            let value: TomlValue = mode == "main" || command.hasPrefix("mode ") || wasString
                ? .string(command) : .array([command, "mode main"])
            setBinding(mode: mode, key: existing ?? shortcut, value: value)
        }
    }
}
