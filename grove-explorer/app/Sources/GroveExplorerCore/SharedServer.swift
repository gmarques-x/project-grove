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
    /// Not an address `URLComponents` can read ("smb://grove lab/media").
    case malformed
    /// The address names a server but no share on it; the scheme as typed.
    case noShare(scheme: String, host: String)

    /// For the Connect to Server sheet, under the field.
    public var sentence: String {
        switch self {
        case .password: "Leave the password out — macOS will ask for it"
        case .unsupportedScheme: "Use an smb://, afp:// or nfs:// address"
        case .empty: "Type the server's address"
        case .malformed: "That isn't a server address"
        case .noShare(let scheme, let host): "Add the share's name: \(scheme)://\(host)/share"
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
        guard var parts = URLComponents(string: text) else { return .failure(.malformed) }
        if parts.password != nil { return .failure(.password) }
        let scheme = parts.scheme?.lowercased() ?? ""
        guard schemes.contains(scheme) else { return .failure(.unsupportedScheme(scheme)) }
        guard let host = parts.host, !host.isEmpty else { return .failure(.empty) }
        var path = parts.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        guard !path.isEmpty else { return .failure(.noShare(scheme: scheme, host: host)) }
        parts.scheme = scheme
        parts.percentEncodedPath = path
        parts.query = nil
        parts.fragment = nil
        guard let url = parts.url else { return .failure(.malformed) }
        return .success(url)
    }

    /// `url` with no password in it: none is ever written or kept (the
    /// address macOS mounted a share by, kept from Locations, can carry one).
    public static func withoutPassword(_ url: URL) -> URL {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.password != nil else { return url }
        parts.password = nil
        return parts.url ?? url
    }
}

/// A saved share's row in the sidebar.
public enum SharedRowState: Equatable, Sendable {
    case notConnected
    case connecting
    /// Mounted, at this folder.
    case connected(URL)

    /// What VoiceOver says of `server`'s row in this state: "media on
    /// grove-lab, shared folder, connected". No user, no password.
    public func spoken(_ server: SharedServer) -> String {
        let state = switch self {
        case .notConnected: "not connected"
        case .connecting: "connecting"
        case .connected: "connected"
        }
        let host = server.host.isEmpty ? "" : " on \(server.host)"
        return "\(server.name)\(host), shared folder, \(state)"
    }
}

/// What a mount ended in: the folder, nothing to say (the password sheet
/// was cancelled), mounted already (EEXIST: the app looks for the volume,
/// `SharedServers.alreadyMounted`), or the sentence for the notice line.
public enum MountOutcome: Equatable, Sendable {
    case mounted(URL)
    case quiet
    case alreadyMounted
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

    /// `servers` with `url` at the end, unless it is saved already (the same
    /// share as `key` compares them, its user included).
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
        let named = servers.filter { folded($0.name) == folded(volumeName) }
        return named.count == 1 ? named[0] : nil
    }

    /// What "Keep in Sidebar" saves for a mounted volume of Locations: the
    /// address macOS keeps to mount it again, any password left out, when
    /// it is one the Connect to Server sheet would take (smb, afp or nfs,
    /// naming a share) and no saved share is it already (a second mount,
    /// `media-1`). Nil: the volume isn't offered Keep in Sidebar (WebDAV,
    /// FTP, a share saved), which would otherwise do nothing.
    public static func keepable(remountURL: URL?, among servers: [SharedServer]) -> URL? {
        guard let remountURL,
            case .success(let url) = SharedAddress.parse(SharedAddress.withoutPassword(remountURL).absoluteString),
            match(mountedRemountURL: url, volumeName: "", among: servers) == nil
        else { return nil }
        return url
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
        case EEXIST:
            // Mounted already, under another spelling of its server (grove-lab.local).
            return .alreadyMounted
        case EAUTH, EACCES, netFSPasswordNeedsChange:
            return .failed("The password was refused")
        case ENOENT, netFSNoSharesAvailable, netAuthNoSharesAvailable:
            return .failed("There is no share called \(share.name) on \(share.host)")
        case ETIMEDOUT, EHOSTDOWN, EHOSTUNREACH, ENETUNREACH:
            return .failed("\(share.host) didn't answer")
        default:
            return .failed(couldNotConnect(to: server, status: status))
        }
    }

    /// The sentence for a status said as it is; also for EEXIST when no
    /// mounted volume turns out to be the share.
    public static func couldNotConnect(to server: URL, status: Int32) -> String {
        "Couldn't connect to \(SharedServer(id: "", url: server).host) (error \(status))"
    }

    /// Which of the mounted volumes (their remount addresses, in order) is
    /// `url`, which NetFS says is mounted already: the one `match` finds;
    /// else the one network volume of the same scheme, user and share on a
    /// server spelled otherwise (`grove-lab.local` for `grove-lab`). Nil
    /// when none is, or several are (never a guess).
    public static func alreadyMounted(_ url: URL, remountURLs: [URL?]) -> Int? {
        let share = SharedServer(id: "", url: url)
        if let exact = remountURLs.firstIndex(where: { remount in
            remount.map { match(mountedRemountURL: $0, volumeName: "", among: [share]) != nil } ?? false
        }) {
            return exact
        }
        let wanted = withoutHost(url, user: url.user != nil)
        let others = remountURLs.indices.filter { index in
            remountURLs[index].map { withoutHost($0, user: url.user != nil) == wanted } ?? false
        }
        return others.count == 1 ? others[0] : nil
    }

    /// `key` with the server left out.
    private static func withoutHost(_ url: URL, user: Bool) -> String {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.absoluteString }
        parts.host = "host"
        parts.port = nil
        return parts.url.map { key($0, user: user) } ?? url.absoluteString
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

    /// A share's address as compared, so that two spellings of one share
    /// are one: the scheme, host and user in any capitals; the path decoded
    /// (`%c3%ba` is `%C3%BA`), in one Unicode form (NFD is NFC) and in any
    /// capitals, as SMB share names are; no slash at the end; port 445 on
    /// smb (its own) as no port. The user is left out when `user` is false.
    public static func key(_ url: URL, user: Bool = true) -> String {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.absoluteString }
        let scheme = (parts.scheme ?? "").lowercased()
        var path = folded(url.path(percentEncoded: false))
        while path.hasSuffix("/") { path.removeLast() }
        let login = user ? parts.user.map { folded($0) + "@" } ?? "" : ""
        let port = parts.port.flatMap { scheme == "smb" && $0 == 445 ? nil : ":\($0)" } ?? ""
        return scheme + "://" + login + folded(parts.host ?? "") + port + path
    }

    /// Text as names are compared: precomposed (NFC), in lower case.
    static func folded(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.lowercased()
    }
}
