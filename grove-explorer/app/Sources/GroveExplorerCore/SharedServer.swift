import Foundation

/// A share saved in the sidebar's SHARED section: `[servers.<id>]` in
/// `explorer.local.toml`, with its `url` (`smb://grove-lab/media`).
public struct SharedServer: Equatable, Sendable, Identifiable {
    /// Its table's name in the file.
    public let id: String
    public let url: URL

    public init(id: String, url: URL) {
        self.id = id
        self.url = url
    }

    /// A share under the id its address gives (`grove-lab-media`).
    public init(url: URL) {
        self.init(id: SharedServers.id(for: url, taken: []), url: url)
    }

    /// The share's name for its row: the address's last part ("media").
    public var name: String { url.lastPathComponent }

    /// The server, said after the name ("grove-lab").
    public var host: String { url.host(percentEncoded: false) ?? "" }
}

/// Why a typed address can't be connected to.
public enum SharedAddressProblem: Error, Equatable, Sendable {
    case password
    case unsupportedScheme(String)
    case empty
    /// The address names a server but no share on it.
    case noShare(host: String)

    /// For the Connect to Server sheet, under the field.
    public var sentence: String {
        switch self {
        case .password: "Leave the password out — macOS will ask for it"
        case .unsupportedScheme: "Use an smb://, afp:// or nfs:// address"
        case .empty: "Type the server's address"
        case .noShare(let host): "Add the share's name: smb://\(host)/share"
        }
    }
}

/// The address typed in the Connect to Server sheet.
public enum SharedAddress {
    static let schemes: Set<String> = ["smb", "afp", "nfs"]

    /// The share `text` names: trimmed, `smb://` added when it has no
    /// scheme, the scheme in lower case and no slash at the end. A user
    /// name is kept; a password is refused, so none is ever saved.
    public static func parse(_ text: String) -> Result<URL, SharedAddressProblem> {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .failure(.empty) }
        if !text.contains("://") { text = "smb://" + text }
        guard var parts = URLComponents(string: text) else { return .failure(.empty) }
        if parts.password != nil { return .failure(.password) }
        let scheme = parts.scheme?.lowercased() ?? ""
        guard schemes.contains(scheme) else { return .failure(.unsupportedScheme(scheme)) }
        guard let host = parts.host, !host.isEmpty else { return .failure(.empty) }
        var path = parts.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        guard !path.isEmpty else { return .failure(.noShare(host: host)) }
        parts.scheme = scheme
        parts.percentEncodedPath = path
        parts.query = nil
        parts.fragment = nil
        guard let url = parts.url else { return .failure(.empty) }
        return .success(url)
    }
}

/// A saved share's row in the sidebar.
public enum SharedRowState: Equatable, Sendable {
    case notConnected
    case connecting
    /// Mounted, at this folder.
    case connected(URL)
}

/// What a mount ended in: the folder, nothing to say (the password sheet
/// was cancelled), or the sentence for the notice line.
public enum MountOutcome: Equatable, Sendable {
    case mounted(URL)
    case quiet
    case failed(String)
}

/// The saved shares as a list to change, and what the app learns of them.
public enum SharedServers {
    /// The id of a new share's table: the host and share as a slug
    /// (`grove-lab-media`), with the first free number on a clash.
    public static func id(for url: URL, taken: Set<String>) -> String {
        let server = SharedServer(id: "", url: url)
        return Favourites.id(forName: server.host + " " + url.path(percentEncoded: false), taken: taken)
    }

    /// `servers` with `url` at the end, unless it is saved already (in any
    /// capitals of its scheme and host, with or without a slash at the end).
    public static func adding(_ url: URL, to servers: [SharedServer]) -> [SharedServer] {
        let key = key(url)
        guard !servers.contains(where: { Self.key($0.url) == key }) else { return servers }
        return servers + [SharedServer(id: id(for: url, taken: Set(servers.map(\.id))), url: url)]
    }

    public static func removing(id: String, from servers: [SharedServer]) -> [SharedServer] {
        servers.filter { $0.id != id }
    }

    /// The saved share a mounted volume is. By the address macOS keeps to
    /// mount it again (`volumeURLForRemountingKey`), which names the user
    /// it logged in as: a share saved without one matches any. Without that
    /// address, by the volume's name, when one saved share alone has it.
    public static func match(mountedRemountURL: URL?, volumeName: String, among servers: [SharedServer]) -> SharedServer? {
        if let mountedRemountURL {
            let withUser = key(mountedRemountURL), withoutUser = key(mountedRemountURL, user: false)
            return servers.first { server in
                server.url.user == nil ? key(server.url, user: false) == withoutUser : key(server.url) == withUser
            }
        }
        let named = servers.filter { $0.name.lowercased() == volumeName.lowercased() }
        return named.count == 1 ? named[0] : nil
    }

    /// A row's state: mounted wins, then a mount on its way.
    public static func state(saved: SharedServer, mounted: URL?, connecting: Bool) -> SharedRowState {
        if let mounted { return .connected(mounted) }
        return connecting ? .connecting : .notConnected
    }

    /// What `NetFSMountURLAsync`'s status says. NetFS.h: positive is an
    /// errno (sys/errno.h), negative an OSStatus, its own codes included.
    public static func outcome(status: Int32, mountPoint: URL?, server: URL) -> MountOutcome {
        if status == 0, let mountPoint { return .mounted(mountPoint) }
        let share = SharedServer(id: "", url: server)
        switch status {
        case userCanceled, ECANCELED:
            return .quiet
        case EAUTH, EACCES, netFSPasswordNeedsChange:
            return .failed("The password was refused")
        case ENOENT, netFSNoSharesAvailable, netAuthNoSharesAvailable:
            return .failed("There is no share called \(share.name) on \(share.host)")
        case ETIMEDOUT, EHOSTDOWN, EHOSTUNREACH, ENETUNREACH:
            return .failed("\(share.host) didn't answer")
        default:
            return .failed("Couldn't connect to \(share.host) (error \(status))")
        }
    }

    // NetFS.h's OSStatus codes (macros Swift doesn't import from it).
    /// userCanceledErr: the password sheet was cancelled.
    static let userCanceled: Int32 = -128
    /// ENETFSPWDNEEDSCHANGE.
    static let netFSPasswordNeedsChange: Int32 = -5045
    /// ENETFSNOSHARESAVAIL.
    static let netFSNoSharesAvailable: Int32 = -5998
    /// kNetAuthErrorNoSharesAvailable (NetAuth/NetAuthErrors.h).
    static let netAuthNoSharesAvailable: Int32 = -6003

    /// A share's address as compared: scheme and host in lower case, no
    /// slash at the end; the user kept unless `user` is false.
    static func key(_ url: URL, user: Bool = true) -> String {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.absoluteString }
        var path = parts.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        let login = user ? parts.percentEncodedUser.map { $0 + "@" } ?? "" : ""
        let port = parts.port.map { ":\($0)" } ?? ""
        return (parts.scheme ?? "").lowercased() + "://" + login + (parts.percentEncodedHost ?? "").lowercased() + port + path
    }
}
