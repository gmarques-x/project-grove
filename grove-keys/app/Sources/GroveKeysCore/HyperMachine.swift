public struct KeyEvent: Sendable {
    public enum Kind: Sendable { case down, up }
    public var kind: Kind
    public var keyCode: UInt16
    public var time: Double // seconds

    public init(kind: Kind, keyCode: UInt16, time: Double) {
        self.kind = kind
        self.keyCode = keyCode
        self.time = time
    }
}

public enum Disposition: Equatable, Sendable {
    case pass, passWithHyper, swallow
}

public enum HyperEffect: Equatable, Sendable {
    case postEscape
    case launch(key: String)
    case showCheatSheet
    case hideCheatSheet
}

/// Pure Hyper logic: F18 held adds ⌃⌥⇧⌘ to other keys, a quick unused tap
/// sends Escape, a long unused hold shows the cheat sheet.
public struct HyperMachine: Sendable {
    public static let f18: UInt16 = 79

    private let settings: HyperSettings
    private let launchKeys: Set<String>
    private var held = false
    private var pressStart = 0.0
    private var used = false
    private var sheetShown = false
    /// Keys pressed while held: their key-up gets the same treatment.
    private var pending: [UInt16: Disposition] = [:]

    public init(settings: HyperSettings, launchKeys: Set<String>) {
        self.settings = settings
        self.launchKeys = launchKeys
    }

    public mutating func handle(_ event: KeyEvent) -> (Disposition, [HyperEffect]) {
        guard settings.enabled else { return (.pass, []) }

        if event.keyCode == Self.f18 {
            switch event.kind {
            case .down:
                if !held {
                    held = true
                    pressStart = event.time
                    used = false
                    sheetShown = false
                }
                return (.swallow, [])
            case .up:
                guard held else { return (.swallow, []) }
                held = false
                if sheetShown {
                    sheetShown = false
                    return (.swallow, [.hideCheatSheet])
                }
                let quick = (event.time - pressStart) * 1000 < Double(settings.tapMs)
                if !used, quick, settings.tap == .escape { return (.swallow, [.postEscape]) }
                return (.swallow, [])
            }
        }

        switch event.kind {
        case .down:
            guard held else { return (.pass, []) }
            used = true
            var effects: [HyperEffect] = []
            if sheetShown {
                sheetShown = false
                effects.append(.hideCheatSheet)
            }
            if let name = KeyNames.name(event.keyCode), launchKeys.contains(name) {
                pending[event.keyCode] = .swallow
                effects.append(.launch(key: name))
                return (.swallow, effects)
            }
            pending[event.keyCode] = .passWithHyper
            return (.passWithHyper, effects)
        case .up:
            return (pending.removeValue(forKey: event.keyCode) ?? .pass, [])
        }
    }

    public mutating func tick(now: Double) -> [HyperEffect] {
        guard settings.enabled, held, !used, !sheetShown, settings.cheatsheetMs > 0,
              now - pressStart >= Double(settings.cheatsheetMs) / 1000 else { return [] }
        sheetShown = true
        return [.showCheatSheet]
    }

    public mutating func reset() -> [HyperEffect] {
        let effects: [HyperEffect] = sheetShown ? [.hideCheatSheet] : []
        held = false
        used = false
        sheetShown = false
        pending = [:]
        return effects
    }
}
