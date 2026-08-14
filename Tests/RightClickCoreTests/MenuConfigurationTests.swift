import Foundation
import Testing
@testable import RightClickCore

struct MenuConfigurationTests {
    @Test
    func roundTripsAndIgnoresUnknownFields() throws {
        let configuration = MenuConfiguration(
            disabledActions: [RightClickAction.copyFilename.configurationID],
            actionOrder: [RightClickAction.openInTerminal.configurationID],
            collapseIntoSubmenu: true,
            monitoredDirectories: ["/Users/example/Projects"]
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

    @Test
    func customCLIAllowsCommandNamesAndAbsoluteExecutablePaths() {
        #expect(CLIProfile.isValidExecutable("gemini"))
        #expect(CLIProfile.isValidExecutable("/opt/homebrew/bin/gemini"))
        #expect(CLIProfile.isValidExecutable("/Applications/AI Tools/gemini-cli"))

        #expect(!CLIProfile.isValidExecutable("bin/gemini"))
        #expect(!CLIProfile.isValidExecutable("gemini --yolo"))
        #expect(!CLIProfile.isValidExecutable("/"))
        #expect(!CLIProfile.isValidExecutable("/opt/homebrew/bin/"))
    }

    @Test
    func configuredCommandQuotesAbsoluteExecutablePath() {
        let command = ShellCommandBuilder.command(
            executable: "/Applications/AI Tools/gemini-cli",
            arguments: ["--resume"],
            in: URL(fileURLWithPath: "/tmp/project")
        )
        #expect(
            command
                == "cd '/tmp/project' && '/Applications/AI Tools/gemini-cli' '--resume'"
        )
    }

    @Test
    func sanitizesTemplateOverridesIndependently() {
        let configuration = MenuConfiguration(templateOverrides: [
            FileTemplate.json.rawValue: TemplateOverride(
                filename: "package.json",
                encoding: "future-encoding"
            ),
            FileTemplate.shell.rawValue: TemplateOverride(
                filename: "../escape.sh",
                encoding: TemplateEncoding.utf8BOM.rawValue
            ),
            "future-template": TemplateOverride(
                filename: "future.txt",
                encoding: TemplateEncoding.utf16.rawValue
            )
        ]).sanitized

        #expect(
            configuration.templateOverride(for: .json)
                == TemplateOverride(filename: "package.json")
        )
        #expect(
            configuration.templateOverride(for: .shell)
                == TemplateOverride(
                    encoding: TemplateEncoding.utf8BOM.rawValue
                )
        )
        #expect(configuration.templateOverrides["future-template"] == nil)
    }

    @Test
    func monitoredDirectoriesSanitizeAbsolutePathsAndDuplicates() {
        let paths = MonitoredDirectoryPolicy.sanitizedPaths([
            "/Users/example/Projects/../Projects",
            "relative/path",
            "/Users/example/Projects",
            "/Volumes/Work"
        ])

        #expect(paths == ["/Users/example/Projects", "/Volumes/Work"])
    }

    @Test
    func monitoredDirectoriesFallBackAndSkipUnavailablePaths() {
        #expect(
            MonitoredDirectoryPolicy.resolvedURLs([], isDirectory: { _ in false })
                == [MonitoredDirectoryPolicy.fallbackURL]
        )

        let resolved = MonitoredDirectoryPolicy.resolvedURLs(
            ["relative", "/Volumes/Missing", "/Users/example/Projects"]
        ) { $0 == "/Users/example/Projects" }
        #expect(
            resolved == [URL(
                fileURLWithPath: "/Users/example/Projects",
                isDirectory: true
            )]
        )

        #expect(
            MonitoredDirectoryPolicy.resolvedURLs(
                ["/Volumes/Missing"],
                isDirectory: { _ in false }
            ) == [MonitoredDirectoryPolicy.fallbackURL]
        )
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
    }
}
