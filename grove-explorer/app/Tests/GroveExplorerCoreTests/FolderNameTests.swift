import Foundation
@testable import GroveExplorerCore
import Testing

/// What the window calls a folder (tabs, the path bar, VoiceOver, the status
/// bar), and the cloud places the sidebar lists under their own headers.
@Suite struct FolderNameTests {
    private let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)

    private func folder(_ path: String) -> URL { URL(fileURLWithPath: path, isDirectory: true) }
    private func title(_ path: String) -> String { FolderName.title(of: folder(path), home: home) }

    private let iCloud = "/Users/someone/Library/Mobile Documents/com~apple~CloudDocs"
    private let storage = "/Users/someone/Library/CloudStorage"

    // MARK: Titles

    @Test func iCloudDriveIsCalledSo() {
        #expect(title(iCloud) == "iCloud Drive")
        #expect(title(iCloud + "/") == "iCloud Drive")
    }

    @Test func aFolderInsideICloudDriveIsCalledByItsName() {
        #expect(title(iCloud + "/Notes") == "Notes")
        #expect(title(iCloud + "/Notes/2026") == "2026")
    }

    @Test func homeIsHomeAndOtherFoldersTheirNames() {
        #expect(title("/Users/someone") == "Home")
        #expect(title("/Users/someone/Library/Mobile Documents") == "Mobile Documents")
        #expect(title("/Users/someone/Library/CloudStorage") == "CloudStorage")
        #expect(title("/Applications") == "Applications")
        #expect(title("/") == "/")
    }

    @Test func aProvidersFolderIsCalledByItsAccount() {
        #expect(title(storage + "/OneDrive-Personal") == "OneDrive")
        #expect(title(storage + "/OneDrive-Contoso") == "OneDrive - Contoso")
        #expect(title(storage + "/OneDrive-Personal/Documents") == "Documents")
    }

    @Test func anotherUsersCloudFoldersAreOnlyFolders() {
        #expect(title("/Users/other/Library/Mobile Documents/com~apple~CloudDocs") == "com~apple~CloudDocs")
        #expect(title("/Users/other/Library/CloudStorage/OneDrive-Personal") == "OneDrive-Personal")
    }

    // MARK: Providers

    @Test func oneDriveReadsAsOneHeaderWhateverTheAccount() throws {
        let personal = try #require(FolderName.provider(folderName: "OneDrive-Personal"))
        #expect(personal == FolderName.Provider(name: "OneDrive", title: "OneDrive"))
        let business = try #require(FolderName.provider(folderName: "OneDrive-Contoso"))
        #expect(business == FolderName.Provider(name: "OneDrive", title: "OneDrive - Contoso"))
        // The account after the first dash, dashes and all.
        #expect(FolderName.provider(folderName: "OneDrive-Contoso-Ltd")?.title == "OneDrive - Contoso-Ltd")
    }

    @Test func otherProvidersHaveTheirOwnNames() {
        #expect(FolderName.provider(folderName: "GoogleDrive-someone@gmail.com")
            == FolderName.Provider(name: "Google Drive", title: "Google Drive - someone@gmail.com"))
        #expect(FolderName.provider(folderName: "Dropbox") == FolderName.Provider(name: "Dropbox", title: "Dropbox"))
        #expect(FolderName.provider(folderName: "Dropbox-Personal")
            == FolderName.Provider(name: "Dropbox", title: "Dropbox"))
        // An account named as the provider is said once.
        #expect(FolderName.provider(folderName: "Box-Box") == FolderName.Provider(name: "Box", title: "Box"))
    }

    @Test func anUnknownProviderIsCalledAsItsFolderSays() {
        #expect(FolderName.provider(folderName: "SyncThing-Work")
            == FolderName.Provider(name: "SyncThing", title: "SyncThing - Work"))
        #expect(FolderName.provider(folderName: "Nextcloud") == FolderName.Provider(name: "Nextcloud", title: "Nextcloud"))
    }

    @Test func hiddenAndEmptyNamesAreNoProvider() {
        #expect(FolderName.provider(folderName: ".DS_Store") == nil)
        #expect(FolderName.provider(folderName: "") == nil)
        #expect(FolderName.provider(folderName: "-Personal") == nil)
    }

    // MARK: The cloud place a folder is in

    @Test func theCloudPlaceAFolderIsIn() throws {
        let drive = try #require(FolderName.cloudPlace(containing: folder(iCloud + "/Notes/2026"), home: home))
        #expect(drive.url.path == iCloud)
        #expect(drive.title == "iCloud Drive")
        #expect(drive.kind == .iCloudDrive)

        let one = try #require(FolderName.cloudPlace(containing: folder(storage + "/OneDrive-Personal/Documents"), home: home))
        #expect(one.url.path == storage + "/OneDrive-Personal")
        #expect(one.title == "OneDrive")
        #expect(one.kind == .provider("OneDrive"))
    }

    @Test func aFolderOutsideEveryCloudPlaceIsInNone() {
        for path in ["/Users/someone", "/Users/someone/Library", storage, "/Users/someone/Library/Mobile Documents",
                     "/Users/someone/Library/Mobile Documents/com~apple~Notes", "/Volumes/Backup", "/"] {
            #expect(FolderName.cloudPlace(containing: folder(path), home: home) == nil, "\(path)")
        }
    }

    @Test func aNameThatOnlyStartsLikeICloudDriveIsNotIt() {
        #expect(FolderName.cloudPlace(containing: folder(iCloud + "2"), home: home) == nil)
        #expect(title(iCloud + "2") == "com~apple~CloudDocs2")
    }

    @Test func dotsInThePathAreWorkedOut() {
        #expect(title(iCloud + "/Notes/..") == "iCloud Drive")
        #expect(FolderName.cloudPlace(containing: folder(storage + "/OneDrive-Personal/a/../b"), home: home)?.title == "OneDrive")
    }

    // MARK: The providers the sidebar lists

    @Test func theSidebarsProvidersAreInTheirFolderOrder() {
        let places = FolderName.providers(in: ["OneDrive-Personal", ".DS_Store", "Dropbox", "OneDrive-Contoso"], home: home)
        #expect(places.map(\.title) == ["Dropbox", "OneDrive", "OneDrive - Contoso"])
        #expect(places.map(\.kind) == [.provider("Dropbox"), .provider("OneDrive"), .provider("OneDrive")])
        #expect(places.map(\.url.path) == [storage + "/Dropbox", storage + "/OneDrive-Personal", storage + "/OneDrive-Contoso"])
    }
}
