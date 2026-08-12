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
            load: { _ in MenuConfiguration(
                terminalProfileID: TerminalProfile.terminal.rawValue
            ) },
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
    func immediateConfigurationEditsAreForwardedAndPersisted() {
        var saveCount = 0
        var forwarded: MenuConfiguration?
        let store = MenuConfigurationStore(
            configurationURL: URL(fileURLWithPath: "/tmp/menu.json"),
            customTemplatesDirectory: URL(fileURLWithPath: "/tmp/Templates"),
            terminalProfileID: TerminalProfile.terminal.rawValue,
            load: { _ in MenuConfiguration(
                terminalProfileID: TerminalProfile.terminal.rawValue
            ) },
            save: { _, _ in saveCount += 1 },
            synchronizeTemplates: { existing, _, _ in existing }
        )
        store.onChange = { forwarded = $0 }

        store.updateImmediately { $0.collapseIntoSubmenu = true }

        #expect(store.configuration.collapseIntoSubmenu)
        #expect(forwarded?.collapseIntoSubmenu == true)
        #expect(saveCount == 1)
    }

    @Test
    func rapidTextEditsRemainPendingAsOneDebouncedSave() {
        var saves: [MenuConfiguration] = []
        let store = makeStore(
            persistenceDelay: .milliseconds(20),
            save: { configuration, _ in saves.append(configuration) }
        )

        for index in 0..<10 {
            var updated = store.configuration
            updated.cliProfiles = [CLIProfile(
                id: "custom",
                title: "Command \(index)",
                executable: "command",
                menuSlot: 1
            )]
            store.replace(with: updated)
        }

        #expect(saves.isEmpty)
        store.flushPendingPersist()
        #expect(saves.count == 1)
        #expect(saves.first?.cliProfiles.first?.title == "Command 9")
    }

    @Test
    func flushPersistsTheLastPendingEditOnlyOnce() async {
        var saves: [MenuConfiguration] = []
        let store = makeStore(
            persistenceDelay: .milliseconds(20),
            save: { configuration, _ in saves.append(configuration) }
        )
        var updated = store.configuration
        updated.copySeparator = ClipboardSeparator.comma.rawValue
        store.replace(with: updated)

        store.flushPendingPersist()
        try? await Task.sleep(for: .milliseconds(80))

        #expect(saves.count == 1)
        #expect(saves.first?.clipboardSeparator == .comma)
    }

    @Test
    func initializationPersistsTheInjectedTerminalProfile() {
        var saves: [MenuConfiguration] = []

        _ = MenuConfigurationStore(
            configurationURL: URL(fileURLWithPath: "/tmp/menu.json"),
            customTemplatesDirectory: URL(fileURLWithPath: "/tmp/Templates"),
            terminalProfileID: TerminalProfile.ghostty.rawValue,
            load: { _ in .default },
            save: { configuration, _ in saves.append(configuration) },
            synchronizeTemplates: { existing, _, _ in existing }
        )

        #expect(saves.count == 1)
        #expect(saves.first?.terminalProfileID == TerminalProfile.ghostty.rawValue)
    }

    private func makeStore(
        persistenceDelay: Duration,
        save: @escaping MenuConfigurationStore.Saver
    ) -> MenuConfigurationStore {
        MenuConfigurationStore(
            configurationURL: URL(fileURLWithPath: "/tmp/menu.json"),
            customTemplatesDirectory: URL(fileURLWithPath: "/tmp/Templates"),
            terminalProfileID: TerminalProfile.terminal.rawValue,
            load: { _ in MenuConfiguration(
                terminalProfileID: TerminalProfile.terminal.rawValue
            ) },
            save: save,
            persistenceDelay: persistenceDelay,
            synchronizeTemplates: { existing, _, _ in existing }
        )
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
