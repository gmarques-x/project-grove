import Foundation
import GroveExplorerCore
import Testing

@Suite struct FileCommandsTests {
    private let downloads = URL(fileURLWithPath: "/Users/me/Downloads", isDirectory: true)
    private let documents = URL(fileURLWithPath: "/Users/me/Documents", isDirectory: true)

    private func file(_ name: String, in folder: URL) -> URL { folder.appendingPathComponent(name) }

    // MARK: Paste

    @Test func pastingIntoAnotherFolderCopiesOrMoves() {
        let items = [file("a.md", in: downloads), file("b.md", in: downloads)]
        #expect(FileCommands.paste(items, into: documents, moving: false) == [.copy(items: items, to: documents)])
        #expect(FileCommands.paste(items, into: documents, moving: true) == [.move(items: items, to: documents)])
    }

    @Test func pastingIntoTheFolderTheItemsCameFromDuplicatesThem() {
        let items = [file("a.md", in: downloads), file("b.md", in: downloads)]
        #expect(FileCommands.paste(items, into: downloads, moving: false) == [.duplicate(items: items)])
        // The folder under another spelling of its path is the same folder.
        let spelled = URL(fileURLWithPath: "/Users/me/Documents/../Downloads/", isDirectory: true)
        #expect(FileCommands.paste(items, into: spelled, moving: false) == [.duplicate(items: items)])
    }

    @Test func aMixedPasteCopiesTheOnesFromElsewhereAndDuplicatesTheOnesFromHere() {
        let here = file("a.md", in: downloads), there = file("b.md", in: documents)
        #expect(
            FileCommands.paste([here, there], into: downloads, moving: false)
                == [.copy(items: [there], to: downloads), .duplicate(items: [here])])
    }

    @Test func movingLeavesOutWhatIsAlreadyHere() {
        let here = file("a.md", in: downloads), there = file("b.md", in: documents)
        #expect(FileCommands.paste([here, there], into: downloads, moving: true) == [.move(items: [there], to: downloads)])
        // All of them are here: the move is made as asked, and the runner
        // refuses it with its sentence ("… is already there").
        #expect(FileCommands.paste([here], into: downloads, moving: true) == [.move(items: [here], to: downloads)])
    }

    @Test func nothingToPasteIsNoOperation() {
        #expect(FileCommands.paste([], into: downloads, moving: false).isEmpty)
        #expect(FileCommands.paste([], into: downloads, moving: true).isEmpty)
    }

    // MARK: Names that exist

    @Test func onlyACopyAndAMoveAskAboutNamesThatExist() {
        let item = file("a.md", in: downloads)
        #expect(FileCommands.asksAboutNames(.copy(items: [item], to: documents)))
        #expect(FileCommands.asksAboutNames(.move(items: [item], to: documents)))
        #expect(!FileCommands.asksAboutNames(.rename(item: item, to: "b.md")))
        #expect(!FileCommands.asksAboutNames(.newFolder(in: documents, name: "x")))
        #expect(!FileCommands.asksAboutNames(.duplicate(items: [item])))
        #expect(!FileCommands.asksAboutNames(.trash(items: [item])))
    }

    @Test func theItemComingForANameThatExists() {
        let a = file("a.md", in: downloads), b = file("b.md", in: downloads)
        let operation = Operation.copy(items: [a, b], to: documents)
        #expect(FileCommands.incoming(for: file("b.md", in: documents), in: operation) == b)
        #expect(FileCommands.incoming(for: file("c.md", in: documents), in: operation) == nil)
        #expect(FileCommands.incoming(for: file("a.md", in: documents), in: .trash(items: [a])) == nil)
    }

    // MARK: New folder

    @Test func aNewFolderIsUntitledFolderOrTheFirstNumberFree() {
        #expect(FileCommands.newFolderName(taken: []) == "untitled folder")
        #expect(FileCommands.newFolderName(taken: ["notes.md"]) == "untitled folder")
        #expect(FileCommands.newFolderName(taken: ["untitled folder"]) == "untitled folder 2")
        #expect(FileCommands.newFolderName(taken: ["untitled folder", "untitled folder 2", "untitled folder 4"]) == "untitled folder 3")
    }

    @Test func aNewFoldersNameIsTakenInAnyCapitals() {
        #expect(FileCommands.newFolderName(taken: ["Untitled Folder"]) == "untitled folder 2")
        #expect(FileCommands.newFolderName(taken: ["UNTITLED FOLDER", "Untitled folder 2"]) == "untitled folder 3")
    }

    // MARK: Rename

    @Test func theRenameFieldSelectsTheNameWithoutItsExtension() {
        #expect(FileCommands.renameSelectionLength(of: "README.md", isFolder: false) == 6)
        #expect(FileCommands.renameSelectionLength(of: "archive.tar.gz", isFolder: false) == 11)
        #expect(FileCommands.renameSelectionLength(of: "LICENSE", isFolder: false) == 7)
    }

    @Test func aFolderAndANameWithoutARealExtensionAreSelectedWhole() {
        #expect(FileCommands.renameSelectionLength(of: "my.project", isFolder: true) == 10)
        #expect(FileCommands.renameSelectionLength(of: ".gitignore", isFolder: false) == 10)
        #expect(FileCommands.renameSelectionLength(of: "notes.", isFolder: false) == 6)
        #expect(FileCommands.renameSelectionLength(of: "", isFolder: false) == 0)
    }

    @Test func theSelectionIsCountedAsTheTextFieldCounts() {
        // UTF-16 units, as NSRange has them: the tree is two.
        #expect(FileCommands.renameSelectionLength(of: "🌲.md", isFolder: false) == 2)
        #expect(FileCommands.renameSelectionLength(of: "café.txt", isFolder: false) == 4)
    }

    // MARK: Paths and Get Info

    @Test func pathsAreCopiedOneToALineInTheOrderGiven() {
        let items = [file("b.md", in: downloads), URL(fileURLWithPath: "/Users/me/Downloads/fonts", isDirectory: true)]
        #expect(FileCommands.pathsText(items) == "/Users/me/Downloads/b.md\n/Users/me/Downloads/fonts")
        #expect(FileCommands.pathsText([]) == "")
    }

    /// The path bar's copy button: the folder's whole path as macOS has it,
    /// never from "~" and never the bar's friendly names ("iCloud Drive"),
    /// with no "/" at its end.
    @Test func aFolderFromThePathBarIsCopiedAsItsRealPath() {
        let iCloud = URL(fileURLWithPath: "/Users/me/Library/Mobile Documents/com~apple~CloudDocs/Notes", isDirectory: true)
        #expect(FileCommands.pathsText([iCloud]) == "/Users/me/Library/Mobile Documents/com~apple~CloudDocs/Notes")
        let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
        #expect(FileCommands.pathsText([home]) == "/Users/me")
    }

    @Test func theGetInfoScriptNamesTheItem() {
        #expect(
            FileCommands.getInfoScript(for: file("notes.md", in: downloads))
                == "tell application \"Finder\" to open information window of (POSIX file \"/Users/me/Downloads/notes.md\" as alias)")
    }

    @Test func aNameCannotEndTheScriptsString() {
        let script = FileCommands.getInfoScript(for: file("a\" & (do shell script \"x\") & \"\\.md", in: downloads))
        #expect(
            script
                == "tell application \"Finder\" to open information window of (POSIX file \"/Users/me/Downloads/a\\\" & (do shell script \\\"x\\\") & \\\"\\\\.md\" as alias)")
    }

    @Test func severalItemsAreOneScript() {
        let items = [file("a.md", in: downloads), file("b \"x\".md", in: downloads)]
        #expect(
            FileCommands.getInfoScript(for: items) == """
                tell application "Finder"
                open information window of (POSIX file "/Users/me/Downloads/a.md" as alias)
                open information window of (POSIX file "/Users/me/Downloads/b \\"x\\".md" as alias)
                end tell
                """)
        // One item: the same script as ever.
        #expect(FileCommands.getInfoScript(for: [items[0]]) == FileCommands.getInfoScript(for: items[0]))
        #expect(FileCommands.getInfoScript(for: []) == "")
    }

    @Test func getInfoOpensUpToTenItemsAtATime() {
        #expect(FileCommands.getInfoLimit == 10)
        #expect(FileCommands.getInfoTooMany == "Get Info opens up to 10 items at a time")
    }
}
