import Foundation
@testable import GroveExplorerCore
import Testing

/// Saved shares: the address typed, the list kept, a mounted volume
/// matched to its row, the row's state and what a mount's result says.
@Suite struct SharedServerTests {
    private func url(_ text: String) -> URL { URL(string: text)! }

    private func server(_ text: String) -> SharedServer { SharedServer(url: url(text)) }

    // MARK: The address

    @Test func parsesTheOwnersShare() {
        let media = url("smb://grove-lab/media")
        #expect(SharedAddress.parse("smb://grove-lab/media") == .success(media))
        #expect(SharedAddress.parse("grove-lab/media") == .success(media))
        #expect(SharedAddress.parse(" smb://grove-lab/media/ ") == .success(media))
        #expect(SharedAddress.parse("SMB://grove-lab/media") == .success(media))
    }

    @Test func keepsAUserRefusesAPassword() throws {
        let withUser = try SharedAddress.parse("smb://gm@grove-lab/media").get()
        #expect(withUser == url("smb://gm@grove-lab/media"))
        #expect(withUser.user == "gm")
        #expect(SharedAddress.parse("smb://gm:secret@grove-lab/media") == .failure(.password))
        #expect(SharedAddress.parse("gm:secret@grove-lab/media") == .failure(.password))
        #expect(SharedAddressProblem.password.sentence == "Leave the password out — macOS will ask for it")
    }

    @Test func schemes() {
        #expect(SharedAddress.parse("afp://grove-lab/media") == .success(url("afp://grove-lab/media")))
        #expect(SharedAddress.parse("nfs://grove-lab/srv/media") == .success(url("nfs://grove-lab/srv/media")))
        #expect(SharedAddress.parse("http://x/y") == .failure(.unsupportedScheme("http")))
        #expect(SharedAddress.parse("") == .failure(.empty))
        #expect(SharedAddress.parse("   ") == .failure(.empty))
        #expect(SharedAddress.parse("smb://grove-lab") == .failure(.noShare(scheme: "smb", host: "grove-lab")))
        #expect(SharedAddress.parse("smb://grove-lab/") == .failure(.noShare(scheme: "smb", host: "grove-lab")))
        #expect(SharedAddress.parse("AFP://grove-lab") == .failure(.noShare(scheme: "afp", host: "grove-lab")))
        #expect(SharedAddress.parse("smb:///media") == .failure(.empty))
    }

    /// What `URLComponents` can't read is no address at all, not an empty one.
    @Test func malformed() {
        #expect(SharedAddress.parse("smb://grove lab/media") == .failure(.malformed))
        #expect(SharedAddress.parse("grove lab/media") == .failure(.malformed))
        #expect(SharedAddress.parse("smb://[grove-lab/media") == .failure(.malformed))
        #expect(SharedAddressProblem.malformed.sentence == "That isn't a server address")
    }

    @Test func sentences() {
        #expect(SharedAddressProblem.unsupportedScheme("http").sentence == "Use an smb://, afp:// or nfs:// address")
        #expect(SharedAddressProblem.empty.sentence == "Type the server's address")
        #expect(SharedAddressProblem.noShare(scheme: "smb", host: "grove-lab").sentence
            == "Add the share's name: smb://grove-lab/share")
        // The scheme that was typed.
        #expect(SharedAddressProblem.noShare(scheme: "afp", host: "grove-lab").sentence
            == "Add the share's name: afp://grove-lab/share")
    }

    @Test func nameAndHost() {
        let media = server("smb://grove-lab/media")
        #expect(media.name == "media")
        #expect(media.host == "grove-lab")
        #expect(media.id == "grove-lab-media")
        #expect(server("smb://grove-lab/My%20Films").name == "My Films")
    }

    // MARK: The saved list

    @Test func idsAreSlugs() {
        #expect(SharedServers.id(for: url("smb://grove-lab/media"), taken: []) == "grove-lab-media")
        #expect(SharedServers.id(for: url("smb://grove-lab/media"), taken: ["grove-lab-media"]) == "grove-lab-media-2")
        #expect(SharedServers.id(for: url("smb://Grove-Lab/My%20Films"), taken: []) == "grove-lab-my-films")
    }

    @Test func savingTheSameShareTwiceKeepsOne() {
        let saved = [server("smb://grove-lab/media")]
        #expect(SharedServers.adding(url("smb://Grove-Lab/media"), to: saved) == saved)
        #expect(SharedServers.adding(url("SMB://grove-lab/media/"), to: saved) == saved)
    }

    @Test func addingPutsTheNewShareAtTheEndUnderAFreeId() {
        let saved = [SharedServer(id: "grove-lab-media", url: url("afp://grove-lab/media"))]
        let added = SharedServers.adding(url("smb://grove-lab/media"), to: saved)
        #expect(added.map(\.id) == ["grove-lab-media", "grove-lab-media-2"])
        #expect(added.last?.url == url("smb://grove-lab/media"))
        // A user name makes another share: it logs in as someone else.
        #expect(SharedServers.adding(url("smb://gm@grove-lab/media"), to: [server("smb://grove-lab/media")]).count == 2)
    }

    /// "The same share" is said as a mounted volume is matched: the share's
    /// name in any capitals and either Unicode form, 445 on smb as no port.
    @Test func savingTheSameShareSpelledAnotherWayKeepsOne() {
        let saved = [server("smb://gm@grove-lab/M%C3%BAsica")]
        #expect(SharedServers.adding(url("smb://GM@grove-lab:445/m%c3%basica/"), to: saved) == saved)
        #expect(SharedServers.adding(url("smb://gm@grove-lab/Mu%CC%81sica"), to: saved) == saved)
        #expect(SharedServers.adding(url("smb://gm@grove-lab:139/M%C3%BAsica"), to: saved).count == 2)
    }

    @Test func removingForgetsOne() {
        let saved = [server("smb://grove-lab/media"), server("smb://grove-lab/backup")]
        #expect(SharedServers.removing(id: "grove-lab-media", from: saved) == [saved[1]])
        #expect(SharedServers.removing(id: "nothing", from: saved) == saved)
    }

    // MARK: A mounted volume's row

    @Test func matchesByRemountURLThenHostAndShare() {
        let media = server("smb://grove-lab/media")
        let backup = server("smb://grove-lab/backup")
        let saved = [media, backup]

        #expect(SharedServers.match(mountedRemountURL: url("smb://grove-lab/media"), volumeName: "media", among: saved) == media)
        // macOS spells it its own way: capitals, a trailing slash, the user it logged in as.
        #expect(SharedServers.match(mountedRemountURL: url("smb://GM@Grove-Lab/media/"), volumeName: "x", among: saved) == media)
        // A second mount of the share is /Volumes/media-1.
        #expect(SharedServers.match(mountedRemountURL: url("smb://grove-lab/media"), volumeName: "media-1", among: saved) == media)
        // Another server's share of the same name is not this one.
        #expect(SharedServers.match(mountedRemountURL: url("smb://nas/media"), volumeName: "media", among: saved) == nil)

        // No remount URL: by the share's name, when only one is called so.
        #expect(SharedServers.match(mountedRemountURL: nil, volumeName: "media", among: saved) == media)
        #expect(SharedServers.match(mountedRemountURL: nil, volumeName: "films", among: saved) == nil)
        let twice = saved + [server("smb://nas/media")]
        #expect(SharedServers.match(mountedRemountURL: nil, volumeName: "media", among: twice) == nil)
    }

    @Test func aSavedUserMustBeTheOneMounted() {
        let mine = server("smb://gm@grove-lab/media")
        #expect(SharedServers.match(mountedRemountURL: url("smb://gm@grove-lab/media"), volumeName: "media", among: [mine]) == mine)
        #expect(SharedServers.match(mountedRemountURL: url("smb://guest@grove-lab/media"), volumeName: "media", among: [mine]) == nil)
    }

    /// SMB share names know no capitals; macOS writes the address its own
    /// way: escapes in either case, the name decomposed, the port, the user.
    @Test func matchesTheShareSpelledAnotherWay() {
        func matches(_ saved: String, _ mounted: String) -> Bool {
            let share = server(saved)
            return SharedServers.match(mountedRemountURL: url(mounted), volumeName: "x", among: [share]) == share
        }
        #expect(matches("smb://grove-lab/Media", "smb://grove-lab/media"))
        #expect(matches("smb://grove-lab/M%c3%basica", "smb://grove-lab/M%C3%BAsica"))
        // NFD (u and a combining acute) against NFC (ú).
        #expect(matches("smb://grove-lab/M%C3%BAsica", "smb://grove-lab/Mu%CC%81sica"))
        #expect(matches("smb://grove-lab/media", "smb://grove-lab:445/media"))
        #expect(matches("smb://grove-lab:445/media", "smb://grove-lab/media"))
        #expect(!matches("smb://grove-lab/media", "smb://grove-lab:139/media"))
        // 445 is smb's alone.
        #expect(!matches("afp://grove-lab/media", "afp://grove-lab:445/media"))
        #expect(matches("smb://GM@grove-lab/media", "smb://gm@grove-lab/media"))
        #expect(matches("smb://gm@grove-lab/media", "SMB://GM@GROVE-LAB/MEDIA"))
        #expect(!matches("smb://grove-lab/media", "smb://grove-lab/media2"))
        #expect(!matches("smb://grove-lab/media", "afp://grove-lab/media"))
    }

    @Test func rowState() {
        let media = server("smb://grove-lab/media")
        let mount = URL(fileURLWithPath: "/Volumes/media", isDirectory: true)
        #expect(SharedServers.state(saved: media, mounted: nil, connecting: false) == .notConnected)
        #expect(SharedServers.state(saved: media, mounted: nil, connecting: true) == .connecting)
        #expect(SharedServers.state(saved: media, mounted: mount, connecting: true) == .connected(mount))
        #expect(SharedServers.state(saved: media, mounted: mount, connecting: false) == .connected(mount))
    }

    // MARK: What a mount's result says

    /// The codes come from the SDK's NetFS/NetFS.h (`NetFSMountURLSync`:
    /// positive is an errno from sys/errno.h, negative an OSStatus) and
    /// sys/errno.h.
    @Test func outcomes() {
        let share = url("smb://grove-lab/media")
        let mount = URL(fileURLWithPath: "/Volumes/media", isDirectory: true)
        func outcome(_ status: Int32, _ mountPoint: URL? = nil) -> MountOutcome {
            SharedServers.outcome(status: status, mountPoint: mountPoint, server: share)
        }

        #expect(outcome(0, mount) == .mounted(mount))
        #expect(outcome(0) == .failed("Couldn't connect to grove-lab (error 0)"))

        // userCanceledErr, ECANCELED: the password sheet was cancelled.
        for status: Int32 in [-128, 89] { #expect(outcome(status) == .quiet) }

        // EAUTH, EACCES, ENETFSPWDNEEDSCHANGE.
        for status: Int32 in [80, 13, -5045] { #expect(outcome(status) == .failed("The password was refused")) }

        // ENOENT, ENETFSNOSHARESAVAIL, kNetAuthErrorNoSharesAvailable.
        for status: Int32 in [2, -5998, -6003] {
            #expect(outcome(status) == .failed("There is no share called media on grove-lab"))
        }

        // ETIMEDOUT, EHOSTDOWN, EHOSTUNREACH, ENETUNREACH.
        for status: Int32 in [60, 64, 65, 51] { #expect(outcome(status) == .failed("grove-lab didn't answer")) }

        // ECONNREFUSED, ENETFSACCOUNTRESTRICTED, ENETFSNOAUTHMECHSUPP,
        // ENETFSNOPROTOVERSSUPP, kNetAuthErrorMountFailed: said as they are.
        for status: Int32 in [61, -5999, -5997, -5996, -6602] {
            #expect(outcome(status) == .failed("Couldn't connect to grove-lab (error \(status))"))
        }
    }
}
