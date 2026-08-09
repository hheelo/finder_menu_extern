import Foundation
import Testing
@testable import RightClickCore

struct MenuConfigurationTests {
    @Test
    func roundTripsAndIgnoresUnknownFields() throws {
        let configuration = MenuConfiguration(
            disabledActions: [RightClickAction.copyFilename.configurationID],
            actionOrder: [RightClickAction.openInTerminal.configurationID],
            collapseIntoSubmenu: true
        )
        let encoded = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(
            MenuConfiguration.self,
            from: encoded
        )
        #expect(decoded == configuration)

        let withUnknownField = """
        {"version":1,"disabledActions":[],"actionOrder":[],
         "collapseIntoSubmenu":false,"futureOption":"ignored"}
        """
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(withUnknownField.utf8).write(to: url)
        #expect(MenuConfigurationFile.load(from: url) == .default)
    }

    @Test
    func missingCorruptAndUnknownVersionsFallBackToDefault() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(MenuConfigurationFile.load(from: url) == .default)

        try Data("not json".utf8).write(to: url)
        #expect(MenuConfigurationFile.load(from: url) == .default)

        try JSONEncoder().encode(
            MenuConfiguration(version: 999, disabledActions: ["copyPath"])
        ).write(to: url)
        #expect(MenuConfigurationFile.load(from: url) == .default)
    }

    @Test
    func hostWritesPrivateFileAndDirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("RightClick/menu.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let configuration = MenuConfiguration(collapseIntoSubmenu: true)
        try MenuConfigurationFile.saveForHost(configuration, to: url)

        #expect(MenuConfigurationFile.load(from: url) == configuration)
        let fileMode = try #require(
            FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]
                as? NSNumber
        ).intValue
        let directoryMode = try #require(
            FileManager.default.attributesOfItem(
                atPath: url.deletingLastPathComponent().path
            )[.posixPermissions] as? NSNumber
        ).intValue
        #expect(fileMode == 0o600)
        #expect(directoryMode == 0o700)
    }

    @Test
    func filtersInvalidAndDuplicateCLIProfilesWithoutLosingBaseMenu() throws {
        let valid = CLIProfile(
            id: "gemini",
            title: "Gemini CLI",
            executable: "gemini",
            arguments: ["--resume", "thread with spaces"],
            menuSlot: 1
        )
        let duplicate = CLIProfile(
            id: "gemini",
            title: "Duplicate",
            executable: "other",
            menuSlot: 2
        )
        let invalid = CLIProfile(
            id: "bad id",
            title: "Invalid",
            executable: "sh -c",
            menuSlot: 3
        )
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try JSONEncoder().encode(
            MenuConfiguration(
                disabledActions: [RightClickAction.copyFilename.configurationID],
                cliProfiles: [valid, duplicate, invalid]
            )
        ).write(to: url)

        let loaded = MenuConfigurationFile.load(from: url)
        #expect(loaded.cliProfiles == [valid])
        #expect(loaded.disabledActions.contains("copyFilename"))
    }

    @Test
    func configuredCommandQuotesEveryArgumentIndividually() {
        let command = ShellCommandBuilder.command(
            executable: "gemini",
            arguments: ["--model", "two words", "it's-safe"],
            in: URL(fileURLWithPath: "/tmp/project folder")
        )
        #expect(
            command
                == "cd '/tmp/project folder' && 'gemini' '--model' 'two words' 'it'\\''s-safe'"
        )
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
    }
}
