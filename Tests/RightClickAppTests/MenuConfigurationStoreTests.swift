import Foundation
import RightClickCore
import Testing

@MainActor
struct MenuConfigurationStoreTests {
    @Test
    func templateChangesPersistOnceAndUnchangedRefreshDoesNotPersist() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let configurationURL = root.appendingPathComponent("Container/menu.json")
        try FileManager.default.createDirectory(
            at: source,
            withIntermediateDirectories: true
        )
        try Data("template".utf8).write(
            to: source.appendingPathComponent("Note.md")
        )

        var saves: [MenuConfiguration] = []
        let store = MenuConfigurationStore(
            configurationURL: configurationURL,
            customTemplatesDirectory: source,
            terminalProfileID: TerminalProfile.terminal.rawValue,
            load: { _ in .default },
            save: { configuration, _ in saves.append(configuration) }
        )

        store.refreshCustomTemplates()
        #expect(saves.count == 1)
        #expect(store.configuration.customTemplates.count == 1)

        store.refreshCustomTemplates()
        #expect(saves.count == 1)

        try FileManager.default.removeItem(
            at: source.appendingPathComponent("Note.md")
        )
        store.refreshCustomTemplates()
        #expect(saves.count == 2)
        #expect(store.configuration.customTemplates.isEmpty)
    }

    @Test
    func configurationEditsAreForwardedAndPersisted() {
        var saveCount = 0
        var forwarded: MenuConfiguration?
        let store = MenuConfigurationStore(
            configurationURL: URL(fileURLWithPath: "/tmp/menu.json"),
            customTemplatesDirectory: URL(fileURLWithPath: "/tmp/Templates"),
            terminalProfileID: TerminalProfile.terminal.rawValue,
            load: { _ in .default },
            save: { _, _ in saveCount += 1 },
            synchronizeTemplates: { existing, _, _ in existing }
        )
        store.onChange = { forwarded = $0 }

        store.update { $0.collapseIntoSubmenu = true }

        #expect(store.configuration.collapseIntoSubmenu)
        #expect(forwarded?.collapseIntoSubmenu == true)
        #expect(saveCount == 1)
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        return directory
    }
}
