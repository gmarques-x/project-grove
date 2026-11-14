import Foundation
@testable import GroveThemesCore
import Testing

/// The cloud providers' names, Grove Explorer's sidebar headers and Grove
/// Keys' cloud pill alike, and the cloud places a list shows.
@Suite struct CloudProvidersTests {
    private let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)

    private let storage = "/Users/someone/Library/CloudStorage"

    // MARK: Providers

    @Test func oneDriveReadsAsOneHeaderWhateverTheAccount() throws {
        let personal = try #require(CloudProviders.provider(folderName: "OneDrive-Personal"))
        #expect(personal == CloudProviders.Provider(name: "OneDrive", title: "OneDrive"))
        let business = try #require(CloudProviders.provider(folderName: "OneDrive-Contoso"))
        #expect(business == CloudProviders.Provider(name: "OneDrive", title: "OneDrive - Contoso"))
        // The account after the first dash, dashes and all.
        #expect(CloudProviders.provider(folderName: "OneDrive-Contoso-Ltd")?.title == "OneDrive - Contoso-Ltd")
    }

    @Test func otherProvidersHaveTheirOwnNames() {
        #expect(CloudProviders.provider(folderName: "GoogleDrive-someone@gmail.com")
            == CloudProviders.Provider(name: "Google Drive", title: "Google Drive - someone@gmail.com"))
        #expect(CloudProviders.provider(folderName: "Dropbox") == CloudProviders.Provider(name: "Dropbox", title: "Dropbox"))
        #expect(CloudProviders.provider(folderName: "Dropbox-Personal")
            == CloudProviders.Provider(name: "Dropbox", title: "Dropbox"))
        // An account named as the provider is said once.
        #expect(CloudProviders.provider(folderName: "Box-Box") == CloudProviders.Provider(name: "Box", title: "Box"))
    }

    @Test func anUnknownProviderIsCalledAsItsFolderSays() {
        #expect(CloudProviders.provider(folderName: "SyncThing-Work")
            == CloudProviders.Provider(name: "SyncThing", title: "SyncThing - Work"))
        #expect(CloudProviders.provider(folderName: "Nextcloud") == CloudProviders.Provider(name: "Nextcloud", title: "Nextcloud"))
    }

    @Test func hiddenAndEmptyNamesAreNoProvider() {
        #expect(CloudProviders.provider(folderName: ".DS_Store") == nil)
        #expect(CloudProviders.provider(folderName: "") == nil)
        #expect(CloudProviders.provider(folderName: "-Personal") == nil)
    }

    // MARK: The providers the sidebar lists

    @Test func theSidebarsProvidersAreInTheirFolderOrder() {
        let places = CloudProviders.providers(in: ["OneDrive-Personal", ".DS_Store", "Dropbox", "OneDrive-Contoso"], home: home)
        #expect(places.map(\.title) == ["Dropbox", "OneDrive", "OneDrive - Contoso"])
        #expect(places.map(\.kind) == [.provider("Dropbox"), .provider("OneDrive"), .provider("OneDrive")])
        #expect(places.map(\.url.path) == [storage + "/Dropbox", storage + "/OneDrive-Personal", storage + "/OneDrive-Contoso"])
    }
}
