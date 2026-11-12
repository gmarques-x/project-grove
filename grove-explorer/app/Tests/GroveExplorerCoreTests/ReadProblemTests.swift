import Foundation
import GroveExplorerCore
import Testing

@Suite struct ReadProblemTests {
    private let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)

    private func sentence(_ path: String, unix: Bool = false, network: Bool = false) -> String {
        ReadProblem.sentence(
            for: .noPermission, folder: URL(fileURLWithPath: path, isDirectory: true), home: home,
            refusedByMode: unix, onNetworkVolume: network)
    }

    /// The folders macOS guards one by one are named as Privacy & Security names them.
    @Test func aGuardedFolderNamesItsFilesAndFoldersPermission() {
        #expect(
            sentence("/Users/someone/Desktop")
                == "Grove Explorer needs the Desktop Folder permission to open Desktop (Privacy & Security › Files and Folders)")
        #expect(sentence("/Users/someone/Documents").contains("the Documents Folder permission to open Documents"))
        #expect(sentence("/Users/someone/Downloads").contains("the Downloads Folder permission to open Downloads"))
    }

    @Test func aFolderInsideAGuardedOneNeedsTheSamePermission() {
        #expect(sentence("/Users/someone/Documents/Work/2026").contains("the Documents Folder permission to open 2026"))
        // Not a folder that only begins with the same letters.
        #expect(!sentence("/Users/someone/Documents-old").contains("Documents Folder"))
    }

    @Test func iCloudDriveAndVolumesHaveTheirOwn() {
        #expect(
            sentence("/Users/someone/Library/Mobile Documents/com~apple~CloudDocs/Notes")
                .contains("the iCloud Drive permission to open Notes"))
        #expect(sentence("/Volumes/Stick/Photos").contains("the Removable Volumes permission to open Photos"))
        #expect(sentence("/Volumes/Share", network: true).contains("the Network Volumes permission to open Share"))
    }

    @Test func anythingElseMacOSRefusesNeedsFullDiskAccess() {
        #expect(
            sentence("/Users/someone/Library/Mail")
                == "Grove Explorer needs Full Disk Access to open Mail (Privacy & Security › Full Disk Access)")
    }

    /// The folder's own mode says no: no setting of macOS's changes that.
    @Test func aFolderClosedByItsModeIsNotAPrivacyMatter() {
        #expect(sentence("/Users/other", unix: true) == "You don't have permission to open other")
        #expect(sentence("/Users/someone/Documents/locked", unix: true) == "You don't have permission to open locked")
    }

    @Test func theOtherProblemsSayWhatHappened() {
        let folder = URL(fileURLWithPath: "/Users/someone/gone", isDirectory: true)
        func words(_ error: FolderReadError) -> String {
            ReadProblem.sentence(for: error, folder: folder, home: home, refusedByMode: false, onNetworkVolume: false)
        }
        #expect(words(.missing) == "gone is no longer there")
        #expect(words(.notAFolder) == "gone is not a folder")
        #expect(words(.other("The disk said no.")) == "The disk said no.")
    }
}
