import Foundation
import RightClickCore
import Testing

@MainActor
struct MenuConfigurationStoreTests {
    @Test
    func templateChangesPersistOnceAndUnchangedRefreshDoesNotPersist() async throws {
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

        await store.refreshCustomTemplates()
        #expect(saves.count == 1)
        #expect(store.configuration.customTemplates.count == 1)

        await store.refreshCustomTemplates()
        #expect(saves.count == 1)

        try FileManager.default.removeItem(
            at: source.appendingPathComponent("Note.md")
        )
        await store.refreshCustomTemplates()
        #expect(saves.count == 2)
        #expect(store.configuration.customTemplates.isEmpty)
    }

    @Test
    func templateSynchronizationDoesNotBlockTheMainActor() async {
        let probe = TemplateSynchronizationProbe()
        let store = MenuConfigurationStore(
            configurationURL: URL(fileURLWithPath: "/tmp/menu.json"),
            customTemplatesDirectory: URL(fileURLWithPath: "/tmp/Templates"),
            terminalProfileID: TerminalProfile.terminal.rawValue,
            load: { _ in MenuConfiguration(
                terminalProfileID: TerminalProfile.terminal.rawValue
            ) },
            save: { _, _ in },
            synchronizeTemplates: { existing, _, _ in
                probe.beginAndWait()
                return TemplateMirrorResult(templates: existing)
            }
        )

        let refresh = Task {
            await store.refreshCustomTemplates()
            probe.complete()
        }
        try? await Task.sleep(for: .milliseconds(30))

        #expect(probe.hasStarted)
        #expect(!probe.hasCompleted)
        probe.release()
        await refresh.value
        #expect(probe.hasCompleted)
    }

    @Test
    func oversizedTemplateWarningDoesNotPreventValidConfigurationCommit() async {
        let template = CustomFileTemplate(
            id: "valid-template",
            title: "Valid.txt",
            filename: "Valid.txt",
            menuSlot: 1
        )
        var saves: [MenuConfiguration] = []
        var failures: [String] = []
        let store = MenuConfigurationStore(
            configurationURL: URL(fileURLWithPath: "/tmp/menu.json"),
            customTemplatesDirectory: URL(fileURLWithPath: "/tmp/Templates"),
            terminalProfileID: TerminalProfile.terminal.rawValue,
            load: { _ in MenuConfiguration(
                terminalProfileID: TerminalProfile.terminal.rawValue
            ) },
            save: { configuration, _ in saves.append(configuration) },
            synchronizeTemplates: { _, _, _ in
                TemplateMirrorResult(
                    templates: [template],
                    skippedOversizedFilenames: ["Oversized.bin"]
                )
            }
        )
        store.onFailure = { failures.append($0) }

        await store.refreshCustomTemplates()

        #expect(store.configuration.customTemplates == [template])
        #expect(saves.count == 1)
        #expect(failures.count == 1)
        #expect(failures[0].contains("Oversized.bin"))
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
            synchronizeTemplates: {
                existing, _, _ in TemplateMirrorResult(templates: existing)
            }
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
            synchronizeTemplates: {
                existing, _, _ in TemplateMirrorResult(templates: existing)
            }
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
            synchronizeTemplates: {
                existing, _, _ in TemplateMirrorResult(templates: existing)
            }
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

private final class TemplateSynchronizationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let releaseSemaphore = DispatchSemaphore(value: 0)
    private var started = false
    private var completed = false

    var hasStarted: Bool { lock.withLock { started } }
    var hasCompleted: Bool { lock.withLock { completed } }

    func beginAndWait() {
        lock.withLock { started = true }
        _ = releaseSemaphore.wait(timeout: .now() + 0.5)
    }

    func release() { releaseSemaphore.signal() }
    func complete() { lock.withLock { completed = true } }
}
