import Foundation
@testable import GroveExplorerCore
import Testing

/// The sidebar's sections and what LOCATIONS lists (2026-11-13 sidebar
/// spec, A): no SHARED section; the saved shares under LOCATIONS, after
/// the disks and before the network volumes that aren't saved; the + on
/// the LOCATIONS header.
@Suite struct SidebarSectionsTests {
    /// A mounted volume as LOCATIONS sees it.
    private struct Disk: Equatable {
        let name: String
        var startup = false
        var network = false
        /// The mount of a saved share: listed on the share's row, not again.
        var saved = false
    }

    private typealias Row = Locations.Row<Disk, String>

    private func rows(_ volumes: [Disk], shares: [String]) -> [Row] {
        Locations.rows(
            volumes: volumes, shares: shares, isStartup: \.startup, isNetwork: \.network, isSavedShare: \.saved)
    }

    // MARK: The sections

    @Test func theSectionsAreFavouritesCloudProvidersLocationsAndTrash() {
        let captions = [SidebarSection.favourites, .cloud, .provider("OneDrive"), .locations, .trash].map(\.caption)
        #expect(captions == ["Favourites", "iCloud", "OneDrive", "Locations", ""])
    }

    @Test func onlyTheLocationsHeaderCarriesThePlus() {
        #expect(SidebarSection.locations.connects)
        for section in [SidebarSection.favourites, .cloud, .provider("OneDrive"), .trash] {
            #expect(!section.connects)
        }
    }

    // MARK: What LOCATIONS lists, in its order

    @Test func theStartupDiskComesFirstThenTheOtherDisksAsListed() {
        let backup = Disk(name: "Backup"), hd = Disk(name: "Macintosh HD", startup: true), stick = Disk(name: "STICK")
        #expect(rows([backup, hd, stick], shares: []) == [.volume(hd), .volume(backup), .volume(stick)])
    }

    @Test func theSavedSharesFollowTheDisksInTheOrderTheyWereAdded() {
        let hd = Disk(name: "Macintosh HD", startup: true), backup = Disk(name: "Backup")
        #expect(rows([hd, backup], shares: ["media", "backup", "photos"])
            == [.volume(hd), .volume(backup), .share("media"), .share("backup"), .share("photos")])
    }

    @Test func aNetworkVolumeThatIsNotSavedComesLastAsListed() {
        let hd = Disk(name: "Macintosh HD", startup: true)
        let films = Disk(name: "films", network: true), backup = Disk(name: "Backup"), docs = Disk(name: "docs", network: true)
        #expect(rows([hd, films, backup, docs], shares: ["media"])
            == [.volume(hd), .volume(backup), .share("media"), .volume(films), .volume(docs)])
    }

    @Test func aSavedSharesMountIsListedOnceOnItsShareRow() {
        let hd = Disk(name: "Macintosh HD", startup: true), media = Disk(name: "media", network: true, saved: true)
        #expect(rows([hd, media], shares: ["media"]) == [.volume(hd), .share("media")])
    }

    @Test func withNothingSavedLocationsIsTheVolumesAlone() {
        let hd = Disk(name: "Macintosh HD", startup: true), films = Disk(name: "films", network: true)
        #expect(rows([hd, films], shares: []) == [.volume(hd), .volume(films)])
        #expect(rows([], shares: ["media"]) == [.share("media")])
    }
}
