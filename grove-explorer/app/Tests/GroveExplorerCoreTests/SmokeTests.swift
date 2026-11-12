import GroveExplorerCore
import GroveThemesCore
import Testing

@Suite struct SmokeTests {
    /// The package builds, and the core reaches the shared library: the TOML
    /// reader explorer.toml will be read with comes from GroveThemesCore.
    @Test func buildsAndLinks() throws {
        #expect(!GroveExplorerInfo.version.isEmpty)
        let config = try TomlDocument.parse("[view]\nshow_hidden = false\n")
        #expect(config.section(["view"])?.entries.map(\.value) == [.bool(false)])
    }
}
