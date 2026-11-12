import Foundation

/// Who is using the network: `/usr/bin/nettop`'s per-process byte counts,
/// two readings apart, as the top apps by traffic. Pure; the Wi-Fi panel's
/// model runs the tool (only while "Show apps" is open).
public enum WifiApps {
    public static let tool = "/usr/bin/nettop"
    /// Per process, CSV, plain numbers, the real interfaces only, five
    /// readings a second apart. Through a pipe the tool hands everything
    /// over when it ends (about 5 s, measured, however few readings are
    /// asked for), so one run is one update: the first reading against the
    /// last.
    public static let arguments = ["-P", "-L", "\(samples)", "-s", "1", "-x", "-t", "external",
                                   "-J", "bytes_in,bytes_out"]
    public static let samples = 5
    /// Seconds between the first and the last reading of a run.
    public static let span = Double(samples - 1)

    /// One process in one reading.
    public struct Reading: Equatable, Sendable {
        /// As nettop writes it, cut at 15 characters ("Google Chrome H").
        public var name: String
        public var pid: Int32
        public var bytesIn: UInt64
        public var bytesOut: UInt64
    }

    /// An app and its traffic, bytes a second.
    public struct App: Equatable, Sendable {
        public var name: String
        public var rate: Double

        public init(name: String, rate: Double) {
            self.name = name
            self.rate = rate
        }
    }

    /// The readings of a run, in order. A reading starts at a header line
    /// (",bytes_in,bytes_out,"); a process's line is "name.pid,in,out,",
    /// read from the right, since a name may hold dots and commas.
    public static func parse(_ output: String) -> [[Reading]] {
        var readings: [[Reading]] = []
        for line in output.split(whereSeparator: \.isNewline) {
            var fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            if fields.last == "" { fields.removeLast() }
            guard fields.count >= 3 else { continue }
            let head = fields.dropLast(2).joined(separator: ",")
            if head.isEmpty {
                readings.append([])
                continue
            }
            guard let bytesIn = UInt64(fields[fields.count - 2]), let bytesOut = UInt64(fields[fields.count - 1]),
                  let dot = head.lastIndex(of: "."), let pid = Int32(head[head.index(after: dot)...]),
                  !readings.isEmpty else { continue }
            readings[readings.count - 1].append(
                Reading(name: String(head[..<dot]), pid: pid, bytesIn: bytesIn, bytesOut: bytesOut))
        }
        return readings
    }

    /// Each process's traffic (in and out together, bytes a second) between
    /// the first and the last reading, `seconds` apart. A process that isn't
    /// in both, or whose counts went backwards, is left out.
    public static func rates(_ readings: [[Reading]], seconds: Double) -> [(reading: Reading, rate: Double)] {
        guard readings.count > 1, seconds > 0, let first = readings.first, let last = readings.last else { return [] }
        let before = Dictionary(first.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        return last.compactMap { now in
            guard let then = before[now.pid], then.name == now.name,
                  now.bytesIn >= then.bytesIn, now.bytesOut >= then.bytesOut else { return nil }
            let bytes = (now.bytesIn - then.bytesIn) + (now.bytesOut - then.bytesOut)
            return (now, Double(bytes) / seconds)
        }
    }

    /// The busiest apps: processes summed under their app's name, those
    /// with no traffic dropped, the largest first (ties by name).
    /// `path`: a process's executable, when the caller can tell (nil
    /// otherwise: the name alone is cleaned).
    public static func top(_ rates: [(reading: Reading, rate: Double)], count: Int = 3,
                           path: (Int32) -> String? = { _ in nil }) -> [App] {
        var sums: [String: Double] = [:]
        for (reading, rate) in rates where rate > 0 {
            sums[appName(process: reading.name, path: path(reading.pid)), default: 0] += rate
        }
        return sums.map { App(name: $0.key, rate: $0.value) }
            .sorted { $0.rate != $1.rate ? $0.rate > $1.rate : $0.name < $1.name }
            .prefix(count).map { $0 }
    }

    /// The app a process belongs to. From its path when known: the
    /// outermost ".app" ("…/Google Chrome.app/…/Google Chrome Helper.app/…"
    /// is Google Chrome); a tool named like a version number takes its
    /// folder's name ("…/claude/versions/2.1.322" is claude). Else from the
    /// name: " Helper" and what follows it, or the " H" nettop's cut leaves
    /// of it, goes.
    public static func appName(process: String, path: String? = nil) -> String {
        if let path {
            let parts = path.split(separator: "/").map(String.init)
            if let bundle = parts.first(where: { $0.hasSuffix(".app") }) {
                return String(bundle.dropLast(4))
            }
            if let last = parts.last, isVersion(last) || isVersion(process) {
                let skipped: Set<String> = ["versions", "version", "bin", "current", "libexec"]
                if let folder = parts.dropLast().last(where: { !isVersion($0) && !skipped.contains($0.lowercased()) }) {
                    return folder
                }
            } else if let last = parts.last, !last.isEmpty, last.hasPrefix(process) {
                // nettop cut the name; the path has it whole.
                return cleaned(last)
            }
        }
        return cleaned(process)
    }

    /// "2.1.322": digits and dots, with a dot.
    static func isVersion(_ text: String) -> Bool {
        text.contains(".") && text.first?.isNumber == true && text.allSatisfy { $0.isNumber || $0 == "." }
    }

    private static func cleaned(_ name: String) -> String {
        var name = name.trimmingCharacters(in: .whitespaces)
        if let helper = name.range(of: " Helper") {
            name = String(name[..<helper.lowerBound])
        } else {
            // What 15 characters leave of "… Helper": " H", " He", … " Helpe".
            for cut in [" Helpe", " Help", " Hel", " He", " H"] where name.count == 15 && name.hasSuffix(cut) {
                name = String(name.dropLast(cut.count))
                break
            }
        }
        return name.isEmpty ? "?" : name
    }
}
