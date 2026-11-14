import Foundation
import GroveExplorerCore
import Testing

@Suite struct CloudTrashTests {
    private let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)

    private func cloud(_ path: String) -> Bool {
        CloudTrash.isCloudItem(URL(fileURLWithPath: path), home: home)
    }

    @Test func cloudFolderPrefixIsExact() {
        #expect(cloud("/Users/me/Library/Mobile Documents/com~apple~CloudDocs/a.txt"))
        #expect(cloud("/Users/me/Library/CloudStorage/OneDrive-Personal/b.txt"))
        #expect(!cloud("/Users/me/Library/Mobile Documents2/x"))
        #expect(!cloud("/Users/me/Library/CloudStorageX/x"))
        #expect(!cloud("/Users/me/Documents/a.txt"))
        #expect(cloud("/Users/me/Documents/../Library/CloudStorage/OneDrive-Personal/c.txt"))
    }

    @Test func finderTrashScriptEscapes() {
        let script = CloudTrash.finderScript(for: URL(fileURLWithPath: "/tmp/a \"b\"\\c.txt"))
        #expect(script == [
            "tell application \"Finder\"",
            "set t to delete (POSIX file \"/tmp/a \\\"b\\\"\\\\c.txt\")",
            "return POSIX path of (t as alias)",
            "end tell",
        ].joined(separator: "\n"))
    }

    @Test func copyIsFixed() {
        #expect(CloudTrash.notAllowed == "Allow Grove Explorer to control Finder in Privacy Settings to move cloud items to the Trash")
        #expect(CloudTrash.finderFailed("x") == "Finder couldn't move it to the Trash: x")
    }
}
