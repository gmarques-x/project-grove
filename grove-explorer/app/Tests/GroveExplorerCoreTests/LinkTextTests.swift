import Foundation
import GroveExplorerCore
import Testing

/// What a symbolic link's row writes after its name: where it points.
@Suite struct LinkTextTests {
    private let home = "/Users/grove"

    // MARK: The target as written

    @Test func anAbsoluteTargetInsideHomeStartsWithATilde() {
        #expect(LinkText.shown("/Users/grove/Library/CloudStorage/OneDrive-Personal/dot-ssh", home: home)
            == "~/Library/CloudStorage/OneDrive-Personal/dot-ssh")
    }

    @Test func homeItselfIsATilde() {
        #expect(LinkText.shown("/Users/grove", home: home) == "~")
        #expect(LinkText.shown("/Users/grove/", home: home) == "~/")
    }

    /// Only home's own folder: a sibling whose name begins with home's is not inside it.
    @Test func anAbsoluteTargetOutsideHomeIsAsStored() {
        #expect(LinkText.shown("/opt/homebrew/bin/git", home: home) == "/opt/homebrew/bin/git")
        #expect(LinkText.shown("/Users/groveother/notes", home: home) == "/Users/groveother/notes")
        #expect(LinkText.shown("/", home: home) == "/")
    }

    /// As `ls -l` shows it: relative stays relative, even when it would end in home.
    @Test func aRelativeTargetIsAsStored() {
        #expect(LinkText.shown("../config/zsh/.zshenv", home: home) == "../config/zsh/.zshenv")
        #expect(LinkText.shown("Users/grove/x", home: home) == "Users/grove/x")
    }

    @Test func anEmptyTargetIsEmpty() {
        #expect(LinkText.shown("", home: home) == "")
    }

    /// A home given with a trailing slash means the same folder.
    @Test func homeWithATrailingSlashIsTheSameHome() {
        #expect(LinkText.shown("/Users/grove/a", home: "/Users/grove/") == "~/a")
    }

    // MARK: Cut in the middle

    @Test func aTargetIsCutInItsMiddleWithNoExtensionKept() {
        #expect(LinkText.middleCut("~/Library/CloudStorage", to: 9) == "~/Li…rage")
        #expect(LinkText.middleCut("short", to: 9) == "short")
        #expect(LinkText.middleCut("abc", to: 0) == "")
        #expect(LinkText.middleCut("abcdef", to: 1) == "…")
    }

    // MARK: What fits

    /// Characters 10 pt wide, an 8 pt gap, "→ " two characters before the target.
    private func fit(name: Int, target: Int, room: Double) -> LinkText.Fit {
        LinkText.fit(nameLength: name, targetLength: target, room: room, advance: 10, gap: 8)
    }

    @Test func everythingFitsWhenThereIsRoom() {
        // 5 + gap + 2 + 10 = 50 + 8 + 120.
        #expect(fit(name: 5, target: 10, room: 178) == LinkText.Fit(nameLength: 5, targetLength: 10))
    }

    /// Short of room, the target is cut first; the name stays whole.
    @Test func theTargetIsCutBeforeTheName() {
        #expect(fit(name: 5, target: 10, room: 177) == LinkText.Fit(nameLength: 5, targetLength: 9))
        #expect(fit(name: 5, target: 10, room: 118) == LinkText.Fit(nameLength: 5, targetLength: 4))
    }

    /// Too little of it would be left to read: it goes, and the name stays whole.
    @Test func aTargetTooCutToReadGoes() {
        #expect(fit(name: 5, target: 10, room: 117) == LinkText.Fit(nameLength: 5, targetLength: nil))
        #expect(fit(name: 5, target: 10, room: 50) == LinkText.Fit(nameLength: 5, targetLength: nil))
    }

    /// A target shorter than the least that is kept is shown only whole.
    @Test func aShortTargetIsWholeOrGone() {
        #expect(fit(name: 5, target: 2, room: 98) == LinkText.Fit(nameLength: 5, targetLength: 2))
        #expect(fit(name: 5, target: 2, room: 97) == LinkText.Fit(nameLength: 5, targetLength: nil))
    }

    /// The name keeps its own truncation: it is cut only once the target has gone.
    @Test func theNameIsCutAsEverOnceTheTargetHasGone() {
        #expect(fit(name: 20, target: 10, room: 120) == LinkText.Fit(nameLength: 12, targetLength: nil))
        #expect(fit(name: 5, target: 10, room: -4) == LinkText.Fit(nameLength: 0, targetLength: nil))
    }

    @Test func noTargetIsNoTarget() {
        #expect(fit(name: 5, target: 0, room: 500) == LinkText.Fit(nameLength: 5, targetLength: nil))
    }

    // MARK: The Kind column

    @Test func aLinksKindSaysWhetherItIsBroken() {
        #expect(LinkText.kind(isBroken: false) == "Symbolic link")
        #expect(LinkText.kind(isBroken: true) == "Broken link")
    }

    /// A link is broken when what it points at can't be reached: missing, or a loop.
    @Test func brokenIsWhenFollowingItFails() {
        #expect(LinkText.isBroken(followError: ENOENT))
        #expect(LinkText.isBroken(followError: ELOOP))
        #expect(LinkText.isBroken(followError: ENOTDIR))
        #expect(!LinkText.isBroken(followError: nil))
        // Not allowed to look is not "broken": the target may well be there.
        #expect(!LinkText.isBroken(followError: EACCES))
        #expect(!LinkText.isBroken(followError: EPERM))
    }
}
