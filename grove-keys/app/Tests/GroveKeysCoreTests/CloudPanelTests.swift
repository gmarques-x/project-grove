import Foundation
import GroveThemesCore
import Testing
@testable import GroveKeysCore

// Invented paths and names only (the repo is public).
private let home = URL(fileURLWithPath: "/Users/someone")
private let iCloud = CloudProviders.iCloudDrivePlace(home: home)
private let oneDrive = CloudProviders.place(
    "OneDrive-Personal", CloudProviders.provider(folderName: "OneDrive-Personal")!, home: home)
private let dropbox = CloudProviders.place(
    "Dropbox", CloudProviders.provider(folderName: "Dropbox")!, home: home)
private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func summary(
    _ items: [(CloudProviders.CloudPlace, String, CloudItemState)] = [],
    places: [CloudProviders.CloudPlace] = [iCloud, oneDrive], firstPassDone: Bool = true,
    access: @escaping (CloudProviders.CloudPlace) -> CloudProviderAccess = { _ in .ok }
) -> CloudSummary {
    var pending = CloudPending()
    for (offset, item) in items.enumerated() {
        pending.update(item.0.url.appendingPathComponent(item.1), root: item.0.url, state: item.2,
                       at: t0.addingTimeInterval(TimeInterval(offset)))
    }
    return CloudSummary(places: places, pending: pending, access: access, firstPassDone: firstPassDone)
}

struct CloudSectionTests {
    @Test func upToDateIsGreenAndQuiet() {
        let sections = CloudSection.sections(summary())
        #expect(sections.map(\.name) == ["iCloud Drive", "OneDrive"])
        for section in sections {
            #expect(section.mark == .synced)
            #expect(section.line == "Up to date")
            #expect(section.tone == .quiet)
            #expect(section.rows.isEmpty)
            #expect(section.showsSettings)
            #expect(!section.offersFilesPrivacy)
            #expect(section.opens == CloudLinks.explorer(section.root))
        }
    }

    @Test func pendingIsYellowWithItsRows() {
        let sections = CloudSection.sections(summary([
            (iCloud, "Notes/plan.txt", .uploading), (iCloud, "photo.heic", .downloading),
        ]))
        #expect(sections[0].mark == .syncing)
        #expect(sections[0].line == "Uploading 1 file · Downloading 1")
        #expect(sections[0].tone == .quiet)
        #expect(sections[0].rows.map(\.name) == ["plan.txt", "photo.heic"])
        #expect(sections[0].rows.map(\.tone) == [.quiet, .quiet])
        #expect(sections[0].rows.map(\.direction) == [.up, .down])
        #expect(sections[0].rows[0].folder == "Notes")
        #expect(sections[0].rows[1].folder == "iCloud Drive")
        #expect(sections[0].rows[0].link == CloudLinks.explorer(iCloud.url.appendingPathComponent("Notes/plan.txt")))
        #expect(sections[1].mark == .synced)
    }

    @Test func aProblemIsRedAndItsRowSaysWhy() {
        var pending = CloudPending()
        let stuck = oneDrive.url.appendingPathComponent("old.txt")
        pending.update(stuck, root: oneDrive.url, state: .notUploaded, at: t0)
        pending.update(oneDrive.url.appendingPathComponent("b.txt"), root: oneDrive.url,
                       state: .problem("couldn't upload"), at: t0)
        pending.expire(at: t0.addingTimeInterval(CloudPending.stuckAfter + 1))
        let sections = CloudSection.sections(CloudSummary(places: [iCloud, oneDrive], pending: pending,
                                                          access: { _ in .ok }, firstPassDone: true))
        let section = sections[1]
        #expect(section.mark == .problem)
        #expect(section.line == "2 problems")
        #expect(section.tone == .error)
        // A provider's error is red; a file that stopped moving is a warning.
        #expect(section.rows.map(\.name) == ["b.txt", "old.txt"])
        #expect(section.rows.map(\.problem) == ["couldn't upload", "not uploading for 30 min"])
        #expect(section.rows.map(\.tone) == [.error, .warning])
        #expect(section.rows.map(\.direction) == [.problem, .problem])
    }

    @Test func notRunningIsRedWithItsSettings() {
        let sections = CloudSection.sections(summary(access: { $0 == oneDrive ? .notRunning : .ok }))
        #expect(sections[1].mark == .problem)
        #expect(sections[1].line == "OneDrive isn't running")
        #expect(sections[1].tone == .error)
        #expect(sections[1].showsSettings)
    }

    @Test func cantSeeIsAWarningWithThePrivacyButton() {
        let sections = CloudSection.sections(summary([(oneDrive, "a.txt", .uploading)],
                                                     access: { $0 == oneDrive ? .cantSee : .ok }))
        #expect(sections[1].mark == .unseen)
        #expect(sections[1].line == "Grove Keys can't see OneDrive's files")
        #expect(sections[1].tone == .warning)
        #expect(sections[1].rows.isEmpty)
        #expect(sections[1].offersFilesPrivacy)
        #expect(!sections[0].offersFilesPrivacy)
    }

    @Test func checkingUntilTheFirstPassSaysSo() {
        let sections = CloudSection.sections(summary([(iCloud, "a.txt", .uploading)], firstPassDone: false))
        #expect(sections[0].mark == .syncing)
        #expect(sections[0].line == "Uploading 1 file")
        // Nothing found yet isn't "Up to date" while it's still looking.
        #expect(sections[1].mark == .checking)
        #expect(sections[1].line == "Checking…")
        #expect(sections[1].tone == .quiet)
    }

    @Test func onlyICloudAndOneDriveHaveSettings() {
        let sections = CloudSection.sections(summary(places: [iCloud, dropbox, oneDrive]))
        #expect(sections.map(\.name) == ["iCloud Drive", "Dropbox", "OneDrive"])
        #expect(sections.map(\.showsSettings) == [true, false, true])
        #expect(sections.map(\.settings) == [.iCloud, nil, .oneDrive])
    }

    @Test func rowsKeepTheirOrderAsTheyChange() {
        let before = CloudSection.sections(summary([
            (iCloud, "c.txt", .uploading), (iCloud, "a.txt", .uploading), (iCloud, "b.txt", .downloading),
        ]))[0].rows.map(\.id)
        let after = CloudSection.sections(summary([
            (iCloud, "c.txt", .downloading), (iCloud, "a.txt", .notUploaded), (iCloud, "b.txt", .uploading),
        ]))[0].rows.map(\.id)
        #expect(before == after)
        #expect(before == ["a.txt", "b.txt", "c.txt"].map { iCloud.url.appendingPathComponent($0).path })
    }

    @Test func theWords() {
        #expect(CloudWords.checking == "Checking…")
        #expect(CloudWords.noFolders == "No cloud folders on this Mac")
        #expect(CloudWords.privacySettings == "Privacy Settings…")
        #expect(CloudLinks.filesPrivacy.absoluteString
            == "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")
        #expect(CloudLinks.systemSettings == "com.apple.systempreferences")
    }
}

struct CloudSampleTests {
    @Test func everySampleIsTheStateItsNamed() {
        #expect(CloudSample.summary("synced").pill == .synced)
        #expect(CloudSample.summary("syncing").pill == .syncing(4))
        #expect(CloudSample.summary("problem").pill == .problem)
        #expect(CloudSample.summary("notrunning").pill == .problem)
        #expect(CloudSample.summary("notrunning").providers[1].access == .notRunning)
        #expect(CloudSample.summary("cantsee").providers[1].access == .cantSee)
        #expect(CloudSample.summary("checking").pill == .checking)
        #expect(CloudSample.summary("none").providers.isEmpty)
        // Anything else is the default.
        #expect(CloudSample.summary("nonsense") == CloudSample.summary("synced"))
    }

    @Test func theSamplesAreInvented() {
        for name in CloudSample.names {
            for provider in CloudSample.summary(name).providers {
                #expect(provider.place.url.path.hasPrefix(CloudSample.home.path + "/"))
                #expect(provider.rows.count <= CloudProviderSummary.rowLimit)
            }
        }
        #expect(CloudSample.home.path == "/Users/someone")
        #expect(CloudSample.summary("syncing").providers[0].rows.count == 3)
    }
}

struct OneDriveSettingsTests {
    @Test(arguments: ["Settings", "Settings…", "Settings...", "settings", "  Preferences…  ", "PREFERENCES"])
    func settingsItems(_ title: String) {
        #expect(OneDriveSettings.isSettingsItem(title))
    }

    @Test(arguments: [nil, "", "Help & Settings", "Sync settings later", "Quit OneDrive", "Pause syncing",
                      "View online", "Setting", "Settings and more"])
    func notSettingsItems(_ title: String?) {
        #expect(!OneDriveSettings.isSettingsItem(title))
    }

    @Test(arguments: ["Help & Settings", "Help and Settings", "help & settings…", " Help &  Settings "])
    func helpAndSettings(_ title: String) {
        #expect(OneDriveSettings.isHelpAndSettings(title))
        #expect(!OneDriveSettings.isSettingsItem(title))
    }

    @Test func theMenuChoice() {
        // Settings itself first, wherever it is; else its submenu.
        #expect(OneDriveSettings.menuChoice(in: ["Help & Settings", "Settings…", "Quit"]) == .press(1))
        #expect(OneDriveSettings.menuChoice(in: [nil, "Preferences"]) == .press(1))
        #expect(OneDriveSettings.menuChoice(in: ["Pause syncing", "Help & Settings", "Quit"]) == .open(1))
        #expect(OneDriveSettings.menuChoice(in: ["Pause syncing", "Quit OneDrive"]) == nil)
        #expect(OneDriveSettings.menuChoice(in: []) == nil)
    }

    @Test func theActivityWindowsSettingsButton() {
        let button = OneDriveSettings.Element.self
        #expect(OneDriveSettings.isSettingsButton(button.init(role: "AXButton", texts: ["Settings"])))
        #expect(OneDriveSettings.isSettingsButton(button.init(role: "AXMenuButton", texts: [nil, "Help & Settings"])))
        #expect(OneDriveSettings.isSettingsButton(button.init(role: "AXPopUpButton", texts: ["", "gearshape"])))
        #expect(OneDriveSettings.isSettingsButton(button.init(role: "AXButton", texts: ["Gear"])))
        #expect(OneDriveSettings.isSettingsButton(button.init(role: "AXButton", texts: ["Open preferences"])))
        // Not a button, or a button about something else.
        #expect(!OneDriveSettings.isSettingsButton(button.init(role: "AXStaticText", texts: ["Settings"])))
        #expect(!OneDriveSettings.isSettingsButton(button.init(role: "AXButton", texts: ["Open folder", "View online"])))
        #expect(!OneDriveSettings.isSettingsButton(button.init(role: "AXButton", texts: ["Gearing up", nil])))
        #expect(!OneDriveSettings.isSettingsButton(button.init(role: nil, texts: ["Settings"])))
    }

    @Test func theButtonChosen() {
        let elements = [
            OneDriveSettings.Element(role: "AXButton", texts: ["Open folder"]),
            OneDriveSettings.Element(role: "AXStaticText", texts: ["Settings"]),
            OneDriveSettings.Element(role: "AXMenuButton", texts: ["Help & Settings"]),
            OneDriveSettings.Element(role: "AXButton", texts: ["Settings"]),
        ]
        // An exact settings button beats the help menu's.
        #expect(OneDriveSettings.settingsButtonIndex(in: elements) == 3)
        #expect(OneDriveSettings.settingsButtonIndex(in: Array(elements.prefix(3))) == 2)
        #expect(OneDriveSettings.settingsButtonIndex(in: Array(elements.prefix(2))) == nil)
    }

    @Test func aSettingsWindowIsTold() {
        #expect(OneDriveSettings.isSettingsWindow("Settings"))
        #expect(OneDriveSettings.isSettingsWindow("OneDrive Settings"))
        #expect(OneDriveSettings.isSettingsWindow("Preferences"))
        #expect(!OneDriveSettings.isSettingsWindow("OneDrive"))
        #expect(!OneDriveSettings.isSettingsWindow(nil))
    }

    @Test func thePressTook() {
        #expect(OneDriveSettings.pressTook(windowsBefore: 1, windowsAfter: 2, titles: []))
        #expect(OneDriveSettings.pressTook(windowsBefore: 1, windowsAfter: 1, titles: ["OneDrive", "Settings"]))
        #expect(!OneDriveSettings.pressTook(windowsBefore: 1, windowsAfter: 1, titles: ["OneDrive"]))
        #expect(!OneDriveSettings.pressTook(windowsBefore: 2, windowsAfter: 1, titles: []))
        #expect(OneDriveSettings.pressTook(menuGone: true, windowsBefore: 1, windowsAfter: 1, titles: []))
    }

    @Test func pressedOnlyWhenEveryStepWorked() {
        let all = OneDriveSettings.Steps(trusted: true, running: true, statusItems: 1, opened: true, found: true,
                                         pressed: true)
        #expect(all.outcome == .pressed)
        #expect(OneDriveSettings.Steps().outcome == .fallback(.notTrusted))
        for change in [\OneDriveSettings.Steps.running, \.opened, \.found, \.pressed] {
            var steps = all
            steps[keyPath: change] = false
            #expect(steps.outcome == .fallback(.notFound))
        }
        var none = all
        none.statusItems = 0
        #expect(none.outcome == .fallback(.notFound))
        var untrusted = all
        untrusted.trusted = false
        #expect(untrusted.outcome == .fallback(.notTrusted))
    }

    @Test func theLines() {
        #expect(OneDriveSettings.Reason.notFound.line == "Open OneDrive's settings from its activity window")
        #expect(OneDriveSettings.Reason.notTrusted.line == "Open OneDrive's settings from its activity window")
        #expect(OneDriveSettings.Reason.notTrusted.permissionLine == "Grove Keys needs Accessibility permission")
        #expect(OneDriveSettings.Reason.notFound.permissionLine == nil)
        #expect(OneDriveSettings.bundleID == "com.microsoft.OneDrive")
    }

    @Test func theHintIsTheVPNsRule() {
        var hint = OneDriveSettings.Hint()
        hint.set(.notFound)
        hint.opened()
        #expect(hint.reason == .notFound)
        hint.opened()
        #expect(hint.reason == nil)
    }
}
