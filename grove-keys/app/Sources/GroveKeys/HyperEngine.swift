import CoreGraphics
import Foundation
import GroveKeysCore
import IOKit.hid

/// The session event tap and the Hyper machine, on a thread of their own so a
/// busy main thread can't make macOS time the tap out. Everything marked "tap
/// thread" is touched only there (the main thread only while no thread runs);
/// effects other than Escape go to the main queue.
final class HyperEngine: @unchecked Sendable {
    static let hyperFlags: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
    static let escape: CGKeyCode = 53

    private let onEffect: @MainActor @Sendable (HyperEffect) -> Void
    /// The tap was disabled three times in a minute; it is off now.
    private let onFailure: @MainActor @Sendable () -> Void

    // Tap thread.
    private var machine = HyperMachine(settings: HyperSettings(), launchKeys: [])
    private var cheatsheetMs = 0
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: CFRunLoopTimer?
    private var disables: [Double] = []

    // Written by the tap thread before `start` returns; read on the main thread.
    private var runLoop: CFRunLoop?
    private var started = false

    init(onEffect: @escaping @MainActor @Sendable (HyperEffect) -> Void,
         onFailure: @escaping @MainActor @Sendable () -> Void) {
        self.onEffect = onEffect
        self.onFailure = onFailure
    }

    var isRunning: Bool { runLoop != nil }

    /// Main thread. Creates the tap; false when macOS refuses it.
    func start(settings: HyperSettings, launchKeys: Set<String>) -> Bool {
        if runLoop != nil { return true }
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            machine = HyperMachine(settings: settings, launchKeys: launchKeys)
            cheatsheetMs = settings.cheatsheetMs
            disables = []
            let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
                | (1 << CGEventType.flagsChanged.rawValue)
            guard let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: CGEventMask(mask), callback: hyperTapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque())
            else {
                started = false
                ready.signal()
                return
            }
            let loop = CFRunLoopGetCurrent()!
            let source = CFMachPortCreateRunLoopSource(nil, port, 0)
            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            self.port = port
            self.source = source
            runLoop = loop
            started = true
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "grove-keys.event-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        return started
    }

    /// Main thread. Resets the machine (its effects still go out), removes the
    /// tap and ends the thread; waits up to a second for that.
    func stop() {
        guard let loop = runLoop else { return }
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
        runLoop = nil
    }

    /// Main thread. New settings or launcher keys; resets the machine first.
    func update(settings: HyperSettings, launchKeys: Set<String>) {
        guard let loop = runLoop else { return }
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
            event.flags.formUnion(Self.hyperFlags)
            return Unmanaged.passUnretained(event)
        }
    }

    /// Re-enables at once; the third time in a minute it gives up instead.
    private func tapDisabled() {
        perform(machine.reset())
        removeTimer()
        guard let port else { return }
        let now = ProcessInfo.processInfo.systemUptime
        disables = disables.filter { now - $0 < 60 } + [now]
        if disables.count >= 3 {
            CGEvent.tapEnable(tap: port, enable: false)
            let onFailure = self.onFailure
            DispatchQueue.main.async { MainActor.assumeIsolated { onFailure() } }
            return
        }
        CGEvent.tapEnable(tap: port, enable: true)
    }

    /// One check when the cheat sheet's time is up; the machine decides.
    private func scheduleTick() {
        removeTimer()
        guard cheatsheetMs > 0, let loop = runLoop else { return }
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
                    CGEvent(keyboardEventSource: source, virtualKey: Self.escape, keyDown: down)?
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
    return Unmanaged<HyperEngine>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
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
