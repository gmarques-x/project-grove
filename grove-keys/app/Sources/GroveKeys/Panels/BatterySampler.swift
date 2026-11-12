import Foundation
import GroveKeysCore
import IOKit
import IOKit.ps

/// The battery, read from IOKit. Every call is a read; none changes anything.
enum BatterySampler {
    /// One reading: the power sources (`IOPSCopyPowerSourcesInfo`: charge,
    /// state, macOS's time estimates), the `AppleSmartBattery` registry entry
    /// (cycles, the Mac's draw, capacity, temperature where published) and
    /// the adapter (`IOPSCopyExternalPowerAdapterDetails`). A millisecond or
    /// two in all.
    static func read() -> BatteryReading {
        BatteryReading(source: internalBattery(), registry: registry(), adapter: adapter())
    }

    private static func internalBattery() -> [String: Any]? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue()
                as? [String: Any], description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            return description
        }
        return nil
    }

    private static func registry() -> [String: Any] {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return [:] }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as? [String: Any] else { return [:] }
        return dictionary
    }

    private static func adapter() -> [String: Any]? {
        IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any]
    }

    /// The health figure of System Settings: `system_profiler
    /// SPPowerDataType`, a tenth of a second. It moves over weeks: asked for
    /// a few times a day at most.
    static func settingsHealth() -> Int? {
        let result = Subprocess.run("/usr/sbin/system_profiler", ["SPPowerDataType"], timeout: 5)
        guard result.status == 0 else { return nil }
        return BatteryHealth.settingsFigure(systemProfiler: result.output)
    }
}
