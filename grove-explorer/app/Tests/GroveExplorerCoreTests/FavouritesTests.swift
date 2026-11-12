import Foundation
import GroveExplorerCore
import Testing

@Suite struct FavouritesTests {
    private let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)

    private func folder(_ path: String) -> URL { URL(fileURLWithPath: path, isDirectory: true) }

    // MARK: A new favourite's id

    @Test func theIdIsTheFoldersNameInLowerCase() {
        #expect(Favourites.id(forName: "Photos", taken: []) == "photos")
    }

    @Test func whatATableNameCantHaveBecomesADash() {
        #expect(Favourites.id(forName: "My Work (2026)", taken: []) == "my-work-2026")
        #expect(Favourites.id(forName: "grove.themes", taken: []) == "grove-themes")
        #expect(Favourites.id(forName: "a_b", taken: []) == "a_b")
    }

    @Test func accentsAreTakenOffTheLetters() {
        #expect(Favourites.id(forName: "Música", taken: []) == "musica")
        // Decomposed: the same name.
        #expect(Favourites.id(forName: "Mu\u{301}sica", taken: []) == "musica")
    }

    @Test func aNameWithNothingUsableIsFolder() {
        #expect(Favourites.id(forName: "/", taken: []) == "folder")
        #expect(Favourites.id(forName: "日本語", taken: []) == "folder")
        #expect(Favourites.id(forName: "", taken: []) == "folder")
    }

    @Test func anIdInUseGetsTheFirstFreeNumber() {
        #expect(Favourites.id(forName: "Photos", taken: ["photos"]) == "photos-2")
        #expect(Favourites.id(forName: "Photos", taken: ["photos", "photos-2", "photos-3"]) == "photos-4")
        // In any capitals: two tables that differ only by case would be told apart by nobody.
        #expect(Favourites.id(forName: "photos", taken: ["Photos"]) == "photos-2")
    }

    // MARK: Adding folders

    @Test func aFolderIsAddedAtTheEndUnderItsName() {
        let old = [Favourite(id: "home", url: home, title: "Home")]
        let added = Favourites.adding([folder("/Users/me/Pictures/Photos")], to: old)
        #expect(added == old + [Favourite(id: "photos", url: folder("/Users/me/Pictures/Photos"), title: "Photos")])
    }

    @Test func aFolderThatIsAFavouriteAlreadyIsNotAddedAgain() {
        let old = [Favourite(id: "home", url: home, title: "Home")]
        #expect(Favourites.adding([home], to: old) == old)
        #expect(Favourites.adding([folder("/Users/me/Documents/../")], to: old) == old)
    }

    @Test func twoFoldersOfOneNameGetTwoIds() {
        let added = Favourites.adding([folder("/a/src"), folder("/b/src"), folder("/a/src")], to: [])
        #expect(added.map(\.id) == ["src", "src-2"])
        #expect(added.map(\.url) == [folder("/a/src"), folder("/b/src")])
    }

    @Test func theDisksTopFolderIsCalledByItsPath() {
        let added = Favourites.adding([folder("/")], to: [])
        #expect(added == [Favourite(id: "folder", url: folder("/"), title: "/")])
    }

    @Test func whatIsAddedCanBeWrittenAndReadBack() throws {
        let added = Favourites.adding([folder("/Users/me/My Work (2026)"), folder("/Volumes/Backup/Música")], to: [])
        let text = try ExplorerConfig.localText(favourites: added, home: home, keeping: nil)
        #expect(ExplorerConfig.allFavourites(tracked: nil, local: text, home: home) == added)
    }
}
