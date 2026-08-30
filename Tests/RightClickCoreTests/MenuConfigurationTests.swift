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
    func detailedLoadingPreservesInvalidBytesAndReason() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = root.appendingPathComponent("menu.json")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false
        )

        #expect(MenuConfigurationFile.loadResult(from: url) == .missing)

        let corrupt = Data("not json".utf8)
        try corrupt.write(to: url)
        #expect(
            MenuConfigurationFile.loadResult(from: url)
                == .invalid(.corrupted, originalData: corrupt)
        )

        let newer = try JSONEncoder().encode(MenuConfiguration(version: 999))
        try newer.write(to: url)
        #expect(
            MenuConfigurationFile.loadResult(from: url)
                == .invalid(.unsupportedVersion(999), originalData: newer)
        )

        let older = try JSONEncoder().encode(MenuConfiguration(version: 0))
        try older.write(to: url)
        #expect(
            MenuConfigurationFile.loadResult(from: url)
                == .invalid(.unsupportedVersion(0), originalData: older)
        )
    }

    @Test
    func detailedLoadResultExposesPersistenceAndRecoveryMetadata() {
        let configuration = MenuConfiguration(collapseIntoSubmenu: true)
        let original = Data("broken".utf8)

        let loaded = MenuConfigurationLoadResult.loaded(configuration)
        #expect(loaded.configuration == configuration)
        #expect(loaded.canPersist)
        #expect(loaded.failure == nil)
        #expect(loaded.originalData == nil)

        let migrated = MenuConfigurationLoadResult.migrated(
            configuration,
            fromVersion: 0
        )
        #expect(migrated.configuration == configuration)
        #expect(migrated.canPersist)

        let missing = MenuConfigurationLoadResult.missing
        #expect(missing.configuration == .default)
        #expect(missing.canPersist)

        let invalid = MenuConfigurationLoadResult.invalid(
            .corrupted,
            originalData: original
        )
        #expect(invalid.configuration == .default)
        #expect(!invalid.canPersist)
        #expect(invalid.failure == .corrupted)
        #expect(invalid.originalData == original)
    }

    @Test
    func recoveryBackupPreservesBytesPrivatelyAndPrunesOldEntries() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("menu.json")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false
        )
        let original = Data("broken".utf8)
        try original.write(to: source)
        let result = MenuConfigurationLoadResult.invalid(
            .corrupted,
            originalData: original
        )

        var latest: URL?
        for index in 0..<(MenuConfigurationBackup.maximumBackupCount + 2) {
            latest = try MenuConfigurationBackup.preserveInvalidConfiguration(
                result,
                sourceURL: source,
                date: Date(timeIntervalSince1970: TimeInterval(index)),
                identifier: UUID(uuidString: String(
                    format: "00000000-0000-0000-0000-%012d",
                    index
                ))!
            )
        }

        let backup = try #require(latest)
        #expect(try Data(contentsOf: backup) == original)
        let backupDirectory = backup.deletingLastPathComponent()
        let files = try FileManager.default.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: nil
        )
        #expect(files.count == MenuConfigurationBackup.maximumBackupCount)
        let mode = try #require(
            FileManager.default.attributesOfItem(atPath: backup.path)[
                .posixPermissions
            ] as? NSNumber
        ).intValue
        #expect(mode == 0o600)
    }

    @Test
    func backupSkipsMissingBytesAndPreservesAnExistingSettingsFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("menu.json")
        defer { try? FileManager.default.removeItem(at: root) }

        let unreadable = MenuConfigurationLoadResult.invalid(
            .unreadable,
            originalData: nil
        )
        #expect(try MenuConfigurationBackup.preserveInvalidConfiguration(
            unreadable,
            sourceURL: source
        ) == nil)
        #expect(try MenuConfigurationBackup.preserveExistingConfiguration(
            at: source
        ) == nil)

        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false
        )
        let original = Data("existing settings".utf8)
        try original.write(to: source)
        let createdBackup = try MenuConfigurationBackup
            .preserveExistingConfiguration(
                at: source,
                date: Date(timeIntervalSince1970: 0),
                identifier: UUID(
                    uuidString: "00000000-0000-4000-8000-000000000001"
                )!
            )
        let backup = try #require(createdBackup)

        #expect(backup.lastPathComponent.contains("-settings-"))
        #expect(try Data(contentsOf: backup) == original)
        let directoryMode = try #require(
            FileManager.default.attributesOfItem(
                atPath: backup.deletingLastPathComponent().path
            )[.posixPermissions] as? NSNumber
        ).intValue
        #expect(directoryMode == 0o700)
    }

    @Test
    func portableSettingsRoundTripPreservesMachineLocalState() throws {
        let localTemplate = CustomFileTemplate(
            id: "local-template",
            title: "Local.md",
            filename: "Local.md",
            menuSlot: 1
        )
        let exported = MenuConfiguration(
            disabledActions: [RightClickAction.copyFilename.configurationID],
            collapseIntoSubmenu: true,
            terminalProfileID: TerminalProfile.iTerm.rawValue,
            cliProfiles: [CLIProfile(
                id: "gemini",
                title: "Gemini",
                executable: "gemini",
                menuSlot: 1
            )],
            customTemplates: [localTemplate]
        )
        let data = try MenuConfigurationTransfer.exportData(exported)
        let current = MenuConfiguration(
            terminalProfileID: TerminalProfile.ghostty.rawValue,
            customTemplates: [localTemplate]
        )

        let imported = try MenuConfigurationTransfer.importData(
            data,
            preservingLocalStateFrom: current
        )

        #expect(imported.collapseIntoSubmenu)
        #expect(imported.cliProfiles.map { $0.id } == ["gemini"])
        #expect(imported.terminalProfileID == TerminalProfile.ghostty.rawValue)
        #expect(imported.customTemplates == [localTemplate])
    }

    @Test
    func portableSettingsStripMachineLocalStateFromTheDocument() throws {
        let localTemplate = CustomFileTemplate(
            id: "local-template",
            title: "Local.md",
            filename: "Local.md",
            menuSlot: 1
        )
        let source = MenuConfiguration(
            disabledActions: [RightClickAction.copyFilename.configurationID],
            terminalProfileID: TerminalProfile.kitty.rawValue,
            customTemplates: [localTemplate]
        )

        let data = try MenuConfigurationTransfer.exportData(source)
        let imported = try MenuConfigurationTransfer.importData(
            data,
            preservingLocalStateFrom: .default
        )

        #expect(imported.disabledActions == source.disabledActions)
        #expect(imported.terminalProfileID == nil)
        #expect(imported.customTemplates.isEmpty)
    }

    @Test
    func portableSettingsRejectMalformedUnsupportedAndOversizedDocuments() throws {
        let current = MenuConfiguration.default

        do {
            _ = try MenuConfigurationTransfer.importData(
                Data("not json".utf8),
                preservingLocalStateFrom: current
            )
            Issue.record("损坏的设置文档本应被拒绝")
        } catch let error as MenuConfigurationTransferError {
            #expect(error == .invalidConfiguration)
        }

        let exported = try MenuConfigurationTransfer.exportData(.default)
        var unsupported = try #require(
            JSONSerialization.jsonObject(with: exported) as? [String: Any]
        )
        unsupported["formatVersion"] = 2
        do {
            _ = try MenuConfigurationTransfer.importData(
                try JSONSerialization.data(withJSONObject: unsupported),
                preservingLocalStateFrom: current
            )
            Issue.record("未知格式版本本应被拒绝")
        } catch let error as MenuConfigurationTransferError {
            #expect(error == .unsupportedFormat)
        }

        var wrongConfigurationVersion = try #require(
            JSONSerialization.jsonObject(with: exported) as? [String: Any]
        )
        var configuration = try #require(
            wrongConfigurationVersion["configuration"] as? [String: Any]
        )
        configuration["version"] = MenuConfiguration.currentVersion + 1
        wrongConfigurationVersion["configuration"] = configuration
        do {
            _ = try MenuConfigurationTransfer.importData(
                try JSONSerialization.data(
                    withJSONObject: wrongConfigurationVersion
                ),
                preservingLocalStateFrom: current
            )
            Issue.record("未知配置版本本应被拒绝")
        } catch let error as MenuConfigurationTransferError {
            #expect(error == .invalidConfiguration)
        }

        let oversized = Data(
            repeating: 0x20,
            count: MenuConfigurationTransfer.maximumDocumentSize + 1
        )
        do {
            _ = try MenuConfigurationTransfer.importData(
                oversized,
                preservingLocalStateFrom: current
            )
            Issue.record("超大设置文档本应被拒绝")
        } catch let error as MenuConfigurationTransferError {
            #expect(error == .documentTooLarge)
        }
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
