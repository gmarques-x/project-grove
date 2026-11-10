import Foundation
import Observation

/// The app's state (Ruling P2): views read it and call `refresh` / `switchTo`.
@MainActor @Observable
public final class ThemesModel {
    public var list: SchemeList?
    public var log: [LogEntry] = []
    /// The scheme being switched to; set while `set` runs.
    public var busyScheme: String?
    public var error: CLIError?
    /// The last switch made from the app, stamped when it ended. The CLI doesn't
    /// log a switch whose configs step failed, so this is the only record of one.
    public private(set) var lastSwitch: LogEntry?

    public var isBusy: Bool { busyScheme != nil }

    /// The switches to show, newest first: the log, led by the last switch made
    /// here when the CLI didn't log it and nothing was logged after it.
    public var switches: [LogEntry] {
        guard let last = lastSwitch, last.configsFailed,
              last.time > (log.first?.time ?? .distantPast) else { return log }
        return [last] + log
    }

    private let client: GroveThemesClient
    private let now: @MainActor () -> Date

    public init(client: GroveThemesClient, now: @escaping @MainActor () -> Date = Date.init) {
        self.client = client
        self.now = now
    }

    /// Reloads the list and the last five switches; clears `error` once the CLI answers.
    public func refresh() async {
        do {
            let list = try await client.list()
            let log = try await client.log(limit: 5)
            self.list = list
            self.log = log
            error = nil
        } catch {
            self.error = Self.cliError(error)
        }
    }

    /// Switches to `scheme`, then refreshes. Ignored while another switch runs.
    public func switchTo(_ scheme: String) async {
        guard busyScheme == nil else { return }
        busyScheme = scheme
        defer { busyScheme = nil }
        var failure: CLIError?
        do {
            let (result, exit) = try await client.set(scheme)
            lastSwitch = LogEntry(time: now(), scheme: result.scheme, exit: Int(exit), steps: result.steps)
        } catch {
            failure = Self.cliError(error)
        }
        await refresh()
        if let failure { error = failure }
    }

    private static func cliError(_ error: any Error) -> CLIError {
        (error as? CLIError) ?? .unreadable(String(describing: error))
    }
}
