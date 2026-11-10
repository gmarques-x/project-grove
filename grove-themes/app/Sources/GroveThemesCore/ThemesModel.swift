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

    public var isBusy: Bool { busyScheme != nil }

    private let client: GroveThemesClient

    public init(client: GroveThemesClient) {
        self.client = client
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
            _ = try await client.set(scheme)
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
