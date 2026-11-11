import CoreGraphics
import Foundation
import GroveKeysCore
import IOKit.hid

/// The session event tap and the Hyper machine, on a thread of their own so a
/// busy main thread can't make macOS time the tap out. Each start makes a new
/// `TapSession` whose state only its own thread touches, so a stop that is
/// slow to finish can't race the next start. Effects other than Escape go to
/// the main queue.
@MainActor
final class HyperEngine {
    nonisolated static let hyperFlags: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
    nonisolated static let escape: CGKeyCode = 53

    private let onEffect: @MainActor @Sendable (HyperEffect) -> Void
    private let onFailure: @MainActor @Sendable () -> Void
    private var session: TapSession?

    /// `onFailure`: re-enabling the tap failed three times in a minute; it is off now.
    init(onEffect: @escaping @MainActor @Sendable (HyperEffect) -> Void,
         onFailure: @escaping @MainActor @Sendable () -> Void) {
        self.onEffect = onEffect
        self.onFailure = onFailure
    }

    var isRunning: Bool { session != nil }

    /// Creates the tap; false when macOS refuses it.
    func start(settings: HyperSettings, launchKeys: Set<String>) -> Bool {
        if session != nil { return true }
        let session = TapSession(settings: settings, launchKeys: launchKeys,
                                 onEffect: onEffect, onFailure: onFailure)
        guard session.start() else { return false }
        self.session = session
        return true
    }

    /// Resets the machine (its effects still go out), removes the tap and ends
    /// the thread; waits up to a second for that.
    func stop() {
        session?.stop()
        session = nil
    }

    /// New settings or launcher keys; resets the machine first.
    func update(settings: HyperSettings, launchKeys: Set<String>) {
        session?.update(settings: settings, launchKeys: launchKeys)
    }
}

/// One run of the tap. After `start` returns, everything but `loop` is touched
/// only on the tap thread.
private final class TapSession: @unchecked Sendable {
    /// A tap disabled again this soon after being re-enabled didn't stay on.
    static let stickSeconds = 1.0

    private let onEffect: @MainActor @Sendable (HyperEffect) -> Void
    private let onFailure: @MainActor @Sendable () -> Void
    private var machine: HyperMachine
    private var cheatsheetMs: Int
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: CFRunLoopTimer?
    private var failures: [Double] = []
    private var lastEnabled = -Double.infinity
    private var gaveUp = false
    /// Set by the tap thread before `start` returns, then read-only.
    private var loop: CFRunLoop?

    init(settings: HyperSettings, launchKeys: Set<String>,
         onEffect: @escaping @MainActor @Sendable (HyperEffect) -> Void,
         onFailure: @escaping @MainActor @Sendable () -> Void) {
        machine = HyperMachine(settings: settings, launchKeys: launchKeys)
        cheatsheetMs = settings.cheatsheetMs
        self.onEffect = onEffect
        self.onFailure = onFailure
    }

    /// Main thread: starts the thread and waits for tapCreate's answer.
    func start() -> Bool {
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in  // the thread keeps its session alive
            let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
                | (1 << CGEventType.flagsChanged.rawValue)
            guard let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: CGEventMask(mask), callback: hyperTapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque())
            else {
                ready.signal()
                return
            }
            let loop = CFRunLoopGetCurrent()!
            let source = CFMachPortCreateRunLoopSource(nil, port, 0)
            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            lastEnabled = ProcessInfo.processInfo.systemUptime
            self.port = port
            self.source = source
            self.loop = loop
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "grove-keys.event-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        return loop != nil
    }

    /// Main thread.
    func stop() {
        guard let loop else { return }
        let done = DispatchSemaphore(value: 0)
        onTapThread(loop) { [self] in
            perform(machine.reset())
            removeTimer()
            if let port {
                CGEvent.tapEnable(tap: port, enable: false)
                CFMachPortInvalidate(port)
            }
            if let source { CFRunLoopRemoveSource(loop, source, .commonModes) }
            port = nil
            source = nil
            CFRunLoopStop(loop)
            done.signal()
        }
        _ = done.wait(timeout: .now() + 1)
    }

    /// Main thread.
    func update(settings: HyperSettings, launchKeys: Set<String>) {
        guard let loop else { return }
        onTapThread(loop) { [self] in
            perform(machine.reset())
            removeTimer()
            machine = HyperMachine(settings: settings, launchKeys: launchKeys)
            cheatsheetMs = settings.cheatsheetMs
        }
    }

    private func onTapThread(_ loop: CFRunLoop, _ block: @escaping () -> Void) {
        CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue, block)
        CFRunLoopWakeUp(loop)
    }

    // MARK: Tap thread

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            tapDisabled()
            return Unmanaged.passUnretained(event)
        case .keyDown, .keyUp:
            break
        default:
            return Unmanaged.passUnretained(event)
        }
        let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let kind: KeyEvent.Kind = type == .keyDown ? .down : .up
        let (disposition, effects) = machine.handle(
            KeyEvent(kind: kind, keyCode: code, time: ProcessInfo.processInfo.systemUptime))
        if code == HyperMachine.f18, kind == .down, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            scheduleTick()
        }
        perform(effects)
        switch disposition {
        case .pass:
            return Unmanaged.passUnretained(event)
        case .swallow:
            return nil
        case .passWithHyper:
            event.flags.formUnion(HyperEngine.hyperFlags)
            return Unmanaged.passUnretained(event)
        }
    }

    /// Re-enables at once. A re-enable that fails (the tap is still off, or
    /// is disabled again within `stickSeconds`) counts; the third failure in
    /// a minute gives up.
    private func tapDisabled() {
        perform(machine.reset())
        removeTimer()
        guard let port, !gaveUp else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let didNotStick = now - lastEnabled < Self.stickSeconds
        CGEvent.tapEnable(tap: port, enable: true)
        lastEnabled = now
        guard didNotStick || !CGEvent.tapIsEnabled(tap: port) else { return }
        failures = failures.filter { now - $0 < 60 } + [now]
        guard failures.count >= 3 else { return }
        gaveUp = true
        CGEvent.tapEnable(tap: port, enable: false)
        let onFailure = self.onFailure
        DispatchQueue.main.async { MainActor.assumeIsolated { onFailure() } }
    }

    /// One check when the cheat sheet's time is up; the machine decides.
    private func scheduleTick() {
        removeTimer()
        guard cheatsheetMs > 0, let loop else { return }
        let fire = CFAbsoluteTimeGetCurrent() + Double(cheatsheetMs) / 1000 + 0.01
        let timer = CFRunLoopTimerCreateWithHandler(nil, fire, 0, 0, 0) { [self] _ in
            self.timer = nil
            perform(machine.tick(now: ProcessInfo.processInfo.systemUptime))
        }
        CFRunLoopAddTimer(loop, timer, .commonModes)
        self.timer = timer
    }

    private func removeTimer() {
        if let timer { CFRunLoopTimerInvalidate(timer) }
        timer = nil
    }

    /// Escape is posted here, in order with the keys around it; the rest goes to the main queue.
    private func perform(_ effects: [HyperEffect]) {
        for effect in effects {
            if effect == .postEscape {
                let source = CGEventSource(stateID: .hidSystemState)
                for down in [true, false] {
                    CGEvent(keyboardEventSource: source, virtualKey: HyperEngine.escape, keyDown: down)?
                        .post(tap: .cghidEventTap)
                }
            } else {
                let onEffect = self.onEffect
                DispatchQueue.main.async { MainActor.assumeIsolated { onEffect(effect) } }
            }
        }
    }
}

private func hyperTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<TapSession>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
}

/// Calls `onMatch` (once, a second after a burst) when a keyboard is connected:
/// new devices start without the hidutil mapping.
@MainActor
final class KeyboardWatcher {
    private let manager: IOHIDManager
    private let onMatch: @MainActor () -> Void
    private var pending: DispatchWorkItem?

    init(onMatch: @escaping @MainActor () -> Void) {
        self.onMatch = onMatch
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Int] = [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
                                       kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, keyboardMatched,
                                                   Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    fileprivate func matched() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.onMatch() }
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: item)
    }
}

private func keyboardMatched(context: UnsafeMutableRawPointer?, result: IOReturn,
                             sender: UnsafeMutableRawPointer?, device: IOHIDDevice) {
    guard let context else { return }
    let watcher = Unmanaged<KeyboardWatcher>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { watcher.matched() }
}
