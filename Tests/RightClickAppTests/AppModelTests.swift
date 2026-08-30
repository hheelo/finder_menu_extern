import Foundation
import RightClickCore
import SwiftUI
import Testing

@MainActor
struct AppModelTests {
    @Test
    func unavailableExtensionDetectionDoesNotPretendItIsDisabled() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        fixture.model.applyExtensionStatus(false)
        fixture.model.applyExtensionStatus(nil)

        #expect(fixture.model.extensionDetectionUnavailable)
        #expect(fixture.model.extensionDiagnosticDetail == L10n.text(
            "diagnostic.unable_to_detect",
            fallback: "无法检测"
        ))
    }

    @Test
    func extensionStatusRefreshesDoNotOverlap() async throws {
        let probe = ExtensionStatusProbe()
        let fixture = try makeFixture(
            extensionStatusProvider: { await probe.detect() }
        )
        defer { fixture.cleanUp() }

        let first = Task { await fixture.model.refreshExtensionStatus() }
        await Task.yield()
        #expect(probe.callCount == 1)

        let second = Task { await fixture.model.refreshExtensionStatus() }
        await second.value
        #expect(probe.callCount == 1)

        probe.complete(with: true)
        await first.value
        #expect(fixture.model.extensionEnabled)
    }

    @Test
    func menuBarSettingNotifiesTheOneWayControllerHook() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        var receivedValues: [Bool] = []
        fixture.model.onMenuBarIconEnabledChange = {
            receivedValues.append($0)
        }

        fixture.model.menuBarIconEnabled = true
        fixture.model.menuBarIconEnabled = false

        #expect(receivedValues == [true, false])
        #expect(fixture.defaults.bool(forKey: "menuBarIconEnabled") == false)
    }

    @Test
    func completingOnboardingPersistsAndDismissesIt() async throws {
        let suiteName = "RightClickAppTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = AppSettings(defaults: defaults)
        let model = AppModel(
            settings: settings,
            notifier: RecordingNotifier(),
            applicationURL: { _ in nil },
            menuConfigurationURL: directory.appendingPathComponent("menu.json"),
            performInitialRefresh: false
        )

        #expect(!model.hasCompletedOnboarding)
        #expect(!model.shouldPresentOnboarding)
        // 构造模型等同深链冷启动：未经过用户可见呈现入口时绝不能弹向导。
        await model.refreshForUserPresentation()
        #expect(model.shouldPresentOnboarding)
        model.completeOnboarding()

        #expect(model.hasCompletedOnboarding)
        #expect(!model.shouldPresentOnboarding)
        #expect(settings.hasCompletedOnboarding)

        await model.refreshForUserPresentation()
        #expect(!model.shouldPresentOnboarding)

        model.restartOnboarding()
        #expect(!model.hasCompletedOnboarding)
        #expect(model.shouldPresentOnboarding)
        #expect(!settings.hasCompletedOnboarding)

        model.skipOnboarding()
        model.completeOnboarding()
        model.completeOnboarding()
        #expect(model.hasCompletedOnboarding)
        #expect(!model.shouldPresentOnboarding)
    }

    @Test
    func trustedCLIDeepLinkExecutesWithoutConfirmation() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }

        let invocation = CLIInvocation(
            command: .codex,
            workingDirectory: fixture.directory,
            authenticationToken: fixture.token
        )
        fixture.model.handle(url: try #require(invocation.deepLink))
        await waitForMainQueue()

        #expect(fixture.executor.invocations == [invocation])
        #expect(fixture.actionLogStore.records().map(\.result) == [
            .received, .succeeded
        ])
    }

    @Test
    func configuredCLILooksUpLocalProfileBeforeExecution() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let profile = CLIProfile(
            id: "gemini-main",
            title: "Gemini",
            executable: "gemini",
            arguments: ["--model", "pro"],
            menuSlot: 1
        )
        fixture.model.menuConfiguration.cliProfiles = [profile]
        fixture.model.persistMenuConfigurationImmediately()
        let invocation = ConfiguredCLIInvocation(
            profileID: profile.id,
            workingDirectory: fixture.directory,
            authenticationToken: fixture.token
        )

        fixture.model.handle(url: try #require(invocation.deepLink))
        await waitForMainQueue()

        #expect(fixture.executor.configuredProfiles == [profile])
        #expect(fixture.executor.configuredDirectories == [fixture.directory])
    }

    @Test
    func movingActionsUsesIndexSetAndDropsLegacyDynamicIdentifiers() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        fixture.model.menuConfiguration.actionOrder = [
            "cli:legacy",
            "template:legacy"
        ]
        let original = fixture.model.configuredMenuActions
        let source = try #require(original.firstIndex(of: .copyFilename))
        let destination = source - 1

        fixture.model.moveMenuActions(
            fromOffsets: IndexSet(integer: source),
            toOffset: destination
        )

        #expect(
            fixture.model.menuConfiguration.actionOrder.allSatisfy {
                RightClickAction(configurationID: $0) != nil
            }
        )
        #expect(
            fixture.model.menuConfiguration.actionOrder.count
                == RightClickAction.allMenuActions.count
        )
        var expected = original
        expected.move(
            fromOffsets: IndexSet(integer: source),
            toOffset: destination
        )
        #expect(fixture.model.configuredMenuActions == expected)
    }

    @Test
    func movingAnActionDownMatchesTheFormerSingleStepBehavior() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let original = fixture.model.configuredMenuActions
        let source = try #require(original.firstIndex(of: .copyFilename))
        let next = source + 1
        #expect(original.indices.contains(next))

        fixture.model.moveMenuActions(
            fromOffsets: IndexSet(integer: source),
            toOffset: source + 2
        )

        var expected = original
        expected.swapAt(source, next)
        #expect(fixture.model.configuredMenuActions == expected)
    }

    @Test
    func restoringDefaultMenuOrderUsesThePublishedNaturalOrder() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let source = try #require(
            fixture.model.configuredMenuActions.firstIndex(of: .copyFilename)
        )
        fixture.model.moveMenuActions(
            fromOffsets: IndexSet(integer: source),
            toOffset: 0
        )

        fixture.model.restoreDefaultMenuActionOrder()

        #expect(fixture.model.menuConfiguration.actionOrder.isEmpty)
        #expect(
            fixture.model.configuredMenuActions
                == RightClickAction.allMenuActions
        )
    }

    @Test
    func removingCLIArgumentIsValidatedAndPersistsOnlyTheTarget() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let profile = CLIProfile(
            id: "profile",
            title: "Profile",
            executable: "command",
            arguments: ["first", "middle", "last"],
            menuSlot: 1
        )
        fixture.model.menuConfiguration.cliProfiles = [profile]
        fixture.model.persistMenuConfigurationImmediately()

        fixture.model.removeCLIArgument(profileID: profile.id, at: 1)
        #expect(
            fixture.model.menuConfiguration.cliProfiles[0].arguments
                == ["first", "last"]
        )

        let unchanged = fixture.model.menuConfiguration
        fixture.model.removeCLIArgument(profileID: profile.id, at: 99)
        fixture.model.removeCLIArgument(profileID: "missing", at: 0)
        #expect(fixture.model.menuConfiguration == unchanged)
        #expect(
            MenuConfigurationFile.load(
                from: fixture.directory.appendingPathComponent("menu.json")
            ).cliProfiles[0].arguments == ["first", "last"]
        )
    }

    @Test
    func menuPreferencesFlowThroughTheConfigurationStore() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }

        #expect(fixture.model.clipboardSeparator == .newline)
        fixture.model.clipboardSeparator = .comma
        #expect(fixture.model.clipboardSeparator == .comma)

        #expect(fixture.model.menuActionIsEnabled(.copyFilename))
        fixture.model.setMenuAction(.copyFilename, isEnabled: false)
        #expect(!fixture.model.menuActionIsEnabled(.copyFilename))
        fixture.model.setMenuAction(.copyFilename, isEnabled: true)
        #expect(fixture.model.menuActionIsEnabled(.copyFilename))

        fixture.model.menuConfiguration.monitoredDirectories = [
            fixture.directory.path,
            fixture.secondDirectory.path
        ]
        fixture.model.removeMonitoredDirectory(fixture.directory.path)
        #expect(fixture.model.menuConfiguration.monitoredDirectories == [
            fixture.secondDirectory.path
        ])
        fixture.model.monitorAllDirectories()
        #expect(fixture.model.menuConfiguration.monitoredDirectories.isEmpty)

        fixture.model.flushPendingMenuConfiguration()
        let persisted = MenuConfigurationFile.load(
            from: fixture.directory.appendingPathComponent("menu.json")
        )
        #expect(persisted.clipboardSeparator == .comma)
        #expect(persisted.disabledActions.isEmpty)
        #expect(persisted.monitoredDirectories.isEmpty)
    }

    @Test
    func customCLIProfileLifecycleReusesSlotsAndReportsTheLimit() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        fixture.model.menuConfiguration.cliProfiles = CLIProfile.validMenuSlots
            .map { slot in
                CLIProfile(
                    id: "profile-\(slot)",
                    title: "Profile \(slot)",
                    executable: "command",
                    menuSlot: slot
                )
            }

        let reusableSlot = 200
        fixture.model.removeCLIProfile(id: "profile-\(reusableSlot)")
        fixture.model.addCLIProfile()

        #expect(fixture.model.menuConfiguration.cliProfiles.count == 400)
        #expect(
            fixture.model.menuConfiguration.cliProfiles.last?.menuSlot
                == reusableSlot
        )

        fixture.model.addCLIProfile()
        #expect(fixture.model.menuConfiguration.cliProfiles.count == 400)
        #expect(fixture.model.errorHistory.first?.message == L10n.text(
            "error.cli_limit",
            fallback: "自定义 CLI 数量已达到上限。"
        ))
    }

    @Test
    func templateOverridesDropDefaultAndEmptyValues() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }

        #expect(fixture.model.templateFilename(for: .text).isEmpty)
        #expect(fixture.model.templateEncoding(for: .text) == .utf8)

        fixture.model.setTemplateFilename("Notes.txt", for: .text)
        fixture.model.setTemplateEncoding(.utf16, for: .text)
        #expect(fixture.model.templateFilename(for: .text) == "Notes.txt")
        #expect(fixture.model.templateEncoding(for: .text) == .utf16)

        fixture.model.setTemplateFilename("", for: .text)
        #expect(fixture.model.templateFilename(for: .text).isEmpty)
        #expect(
            fixture.model.menuConfiguration.templateOverrides["text"]
                != nil
        )

        fixture.model.setTemplateEncoding(.utf8, for: .text)
        #expect(
            fixture.model.menuConfiguration.templateOverrides["text"]
                == nil
        )
        fixture.model.flushPendingMenuConfiguration()
    }

    @Test
    func multipleTrustedCLIRequestsExecuteWithoutAWindowQueue() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }

        let first = CLIInvocation(
            command: .codex,
            workingDirectory: fixture.directory,
            authenticationToken: fixture.token
        )
        let second = CLIInvocation(
            command: .claude,
            workingDirectory: fixture.secondDirectory,
            authenticationToken: fixture.token
        )

        fixture.model.handle(url: try #require(first.deepLink))
        fixture.model.handle(url: try #require(second.deepLink))
        await waitForMainQueue()

        #expect(fixture.executor.invocations == [first, second])
    }

    @Test
    func selectedTerminalWindowBehaviorFlowsToExecutor() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        fixture.model.terminalWindowBehavior = .newWindow
        let invocation = CLIInvocation(
            command: .codex,
            workingDirectory: fixture.directory,
            authenticationToken: fixture.token
        )

        fixture.model.handle(url: try #require(invocation.deepLink))
        await waitForMainQueue()

        #expect(fixture.executor.windowBehaviors == [.newWindow])
    }

    @Test
    func terminalScriptsDistinguishTabsFromWindows() {
        let terminalTab = ActionExecutor.appleScript(
            terminalProfile: .terminal,
            terminalWindowBehavior: .newTab
        )
        let terminalWindow = ActionExecutor.appleScript(
            terminalProfile: .terminal,
            terminalWindowBehavior: .newWindow
        )
        let iTermTab = ActionExecutor.appleScript(
            terminalProfile: .iTerm,
            terminalWindowBehavior: .newTab
        )
        let iTermWindow = ActionExecutor.appleScript(
            terminalProfile: .iTerm,
            terminalWindowBehavior: .newWindow
        )

        #expect(terminalTab.contains("keystroke \"t\""))
        #expect(terminalTab.contains("count of windows) is 0"))
        #expect(!terminalWindow.contains("keystroke \"t\""))
        #expect(iTermTab.contains("create tab with default profile"))
        #expect(iTermTab.contains("count of windows) is 0"))
        #expect(!iTermWindow.contains("create tab with default profile"))
    }

    @Test
    func knownMissingCLIIsRejectedBeforeOpeningTerminal() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let token = ExtensionRequestTokenStore.makeToken()
        let executor = RecordingExecutor()
        let coordinator = DeepLinkCoordinator(
            extensionRequestToken: { token },
            executor: executor,
            applicationURL: { _ in nil }
        )
        let invocation = CLIInvocation(
            command: .codex,
            workingDirectory: directory,
            authenticationToken: token
        )
        var failures: [String] = []

        coordinator.dispatch(
            try #require(invocation.deepLink),
            terminalProfile: .terminal,
            commandAvailability: { _ in false }
        ) { event in
            if case let .trustedFailure(message) = event {
                failures.append(message)
            }
        }
        await waitForMainQueue()

        #expect(executor.invocations.isEmpty)
        #expect(failures.count == 1)
        #expect(failures[0].contains("codex"))
    }

    @Test
    func unsignedCLIDeepLinkIsRejectedWithoutExecuting() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }

        let invocation = CLIInvocation(
            command: .codex,
            workingDirectory: fixture.directory
        )
        fixture.model.handle(url: try #require(invocation.deepLink))
        await waitForMainQueue()

        #expect(fixture.executor.invocations.isEmpty)
        #expect(fixture.model.errorHistory.isEmpty)
        #expect(fixture.notifier.messages.isEmpty)
        #expect(fixture.actionLogStore.records().isEmpty)
    }

    @Test
    func invalidDeepLinkIsRejectedWithoutExecuting() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }

        fixture.model.handle(url: URL(string: "https://example.com")!)
        await waitForMainQueue()

        #expect(fixture.model.errorHistory.isEmpty)
        #expect(fixture.notifier.messages.isEmpty)
        #expect(fixture.executor.invocations.isEmpty)
    }

    @Test
    func authenticatedErrorIsNotifiedAndStored() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let invocation = ErrorInvocation(
            message: "没有写入权限。",
            authenticationToken: fixture.token
        )

        fixture.model.handle(url: try #require(invocation.deepLink))
        await waitForMainQueue()

        #expect(fixture.notifier.messages == ["没有写入权限。"])
        #expect(fixture.model.errorHistory.map(\.message) == ["没有写入权限。"])
    }

    @Test
    func repeatedVisibleFailureKeepsOnlyTheLatestHistoryEntry() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let first = ErrorInvocation(
            message: "持续失败。",
            authenticationToken: fixture.token
        )
        let second = ErrorInvocation(
            message: "持续失败。",
            authenticationToken: fixture.token
        )

        fixture.model.handle(url: try #require(first.deepLink))
        await waitForMainQueue()
        let original = try #require(fixture.model.errorHistory.first)

        fixture.model.handle(url: try #require(second.deepLink))
        await waitForMainQueue()

        #expect(fixture.model.errorHistory.map(\.message) == ["持续失败。"])
        let replacement = try #require(fixture.model.errorHistory.first)
        #expect(replacement.id != original.id)
        #expect(replacement.date >= original.date)
        #expect(fixture.notifier.messages == ["持续失败。", "持续失败。"])
    }

    @Test
    func trustedExecutionFailureIsNotified() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        fixture.executor.failureMessage = "终端拒绝了自动化请求。"
        let invocation = CLIInvocation(
            command: .codex,
            workingDirectory: fixture.directory,
            authenticationToken: fixture.token
        )

        fixture.model.handle(url: try #require(invocation.deepLink))
        await waitForMainQueue()

        #expect(fixture.notifier.messages == ["终端拒绝了自动化请求。"])
        #expect(fixture.model.errorHistory.count == 1)
        let logRecords = fixture.actionLogStore.records()
        #expect(logRecords.map(\.result) == [.received, .failed])
        #expect(logRecords.last?.errorCategory == .executionFailed)
    }

    @Test
    func unsignedOpenRequestIsRejectedSilently() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let invocation = OpenInvocation(
            application: .visualStudioCode,
            targets: [fixture.directory]
        )

        fixture.model.handle(url: try #require(invocation.deepLink))
        await waitForMainQueue()

        #expect(fixture.notifier.messages.isEmpty)
        #expect(fixture.model.errorHistory.isEmpty)
    }

    @Test
    func authenticatedOpenFailureIsNotified() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let invocation = OpenInvocation(
            application: .visualStudioCode,
            targets: [fixture.directory],
            authenticationToken: fixture.token
        )

        fixture.model.handle(url: try #require(invocation.deepLink))
        await waitForMainQueue()

        #expect(fixture.notifier.messages.count == 1)
        #expect(fixture.model.errorHistory.count == 1)
    }

    @Test
    func localActionSessionLifecycleAndErrorClearingFlowThroughTheModel() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let markerURL = fixture.directory.appendingPathComponent(
            "host-session.active"
        )

        fixture.model.beginLocalActionLogSession()
        fixture.model.beginLocalActionLogSession()
        #expect(FileManager.default.fileExists(atPath: markerURL.path))
        #expect(
            fixture.actionLogStore.records().map(\.result) == [.started]
        )

        fixture.model.recordFailure("first")
        fixture.model.recordFailure("second")
        #expect(fixture.model.errorHistory.map(\.message) == ["second", "first"])
        fixture.model.clearErrors()
        #expect(fixture.model.errorHistory.isEmpty)

        fixture.model.endLocalActionLogSession()
        fixture.model.endLocalActionLogSession()
        #expect(
            fixture.actionLogStore.records().map(\.result)
                == [.started, .succeeded]
        )
        #expect(!FileManager.default.fileExists(atPath: markerURL.path))
        #expect(
            LocalActionLogStore.load(
                from: fixture.directory.appendingPathComponent(
                    "action-log.json"
                )
            ).map(\.result) == [.started, .succeeded]
        )
    }

    @Test
    func explicitRecoveryResetReplacesCorruptConfiguration() throws {
        let corrupt = Data("not json".utf8)
        let fixture = try makeFixture(menuConfigurationData: corrupt)
        defer { fixture.cleanUp() }

        #expect(fixture.model.configurationRecoveryRequired)
        #expect(!fixture.model.errorHistory.isEmpty)

        fixture.model.resetConfigurationAfterRecovery()

        #expect(!fixture.model.configurationRecoveryRequired)
        #expect(fixture.model.menuConfiguration.terminalProfileID == "terminal")
        #expect(fixture.model.lastStatus == L10n.text(
            "status.reset_settings",
            fallback: "Finder 菜单设置已重置"
        ))
        #expect(
            MenuConfigurationFile.load(
                from: fixture.directory.appendingPathComponent("menu.json")
            ) == fixture.model.menuConfiguration
        )
        let backups = try FileManager.default.contentsOfDirectory(
            at: fixture.directory.appendingPathComponent("Backups"),
            includingPropertiesForKeys: nil
        )
        #expect(backups.count == 2)
        #expect(backups.allSatisfy { $0.pathExtension == "json" })
    }

    private func makeFixture(
        extensionStatusProvider: (@MainActor () async -> Bool?)? = nil,
        menuConfigurationData: Data? = nil
    ) throws -> Fixture {
        let suiteName = "RightClickAppTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let directory = try makeDirectory()
        let secondDirectory = try makeDirectory()
        if let menuConfigurationData {
            try menuConfigurationData.write(
                to: directory.appendingPathComponent("menu.json")
            )
        }
        let executor = RecordingExecutor()
        let notifier = RecordingNotifier()
        let token = ExtensionRequestTokenStore.makeToken()
        let settings = AppSettings(defaults: defaults)
        settings.terminalProfile = .terminal
        let actionLogStore = LocalActionLogStore(
            fileURL: directory.appendingPathComponent("action-log.json")
        )
        let model = AppModel(
            settings: settings,
            executor: executor,
            extensionRequestToken: { token },
            notifier: notifier,
            applicationURL: { _ in nil },
            menuConfigurationURL: directory.appendingPathComponent(
                "menu.json"
            ),
            actionLogStore: actionLogStore,
            extensionStatusProvider: extensionStatusProvider,
            performInitialRefresh: false
        )
        return Fixture(
            model: model,
            executor: executor,
            notifier: notifier,
            actionLogStore: actionLogStore,
            token: token,
            defaults: defaults,
            suiteName: suiteName,
            directory: directory,
            secondDirectory: secondDirectory
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

    private func waitForMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}

@MainActor
private final class ExtensionStatusProbe {
    private(set) var callCount = 0
    private var continuation: CheckedContinuation<Bool?, Never>?

    func detect() async -> Bool? {
        callCount += 1
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func complete(with result: Bool?) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

@MainActor
private final class RecordingExecutor: CLIExecuting {
    private(set) var invocations: [CLIInvocation] = []
    private(set) var windowBehaviors: [TerminalWindowBehavior] = []
    private(set) var openedDirectories: [URL] = []
    private(set) var configuredProfiles: [CLIProfile] = []
    private(set) var configuredDirectories: [URL] = []
    var failureMessage: String?

    func openDirectory(
        _ directory: URL,
        terminalProfile: TerminalProfile,
        terminalWindowBehavior: TerminalWindowBehavior
    ) async throws {
        openedDirectories.append(directory)
        windowBehaviors.append(terminalWindowBehavior)
        if let failureMessage {
            throw TestExecutionError(message: failureMessage)
        }
    }

    func execute(
        _ invocation: CLIInvocation,
        terminalProfile: TerminalProfile,
        terminalWindowBehavior: TerminalWindowBehavior
    ) async throws {
        invocations.append(invocation)
        windowBehaviors.append(terminalWindowBehavior)
        if let failureMessage {
            throw TestExecutionError(message: failureMessage)
        }
    }

    func executeConfigured(
        _ profile: CLIProfile,
        workingDirectory: URL,
        terminalProfile: TerminalProfile,
        terminalWindowBehavior: TerminalWindowBehavior
    ) async throws {
        configuredProfiles.append(profile)
        configuredDirectories.append(workingDirectory)
        windowBehaviors.append(terminalWindowBehavior)
        if let failureMessage {
            throw TestExecutionError(message: failureMessage)
        }
    }
}

private struct TestExecutionError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
private final class RecordingNotifier: UserNotifying {
    private(set) var messages: [String] = []

    func report(_ message: String) {
        messages.append(message)
    }
}

@MainActor
private struct Fixture {
    let model: AppModel
    let executor: RecordingExecutor
    let notifier: RecordingNotifier
    let actionLogStore: LocalActionLogStore
    let token: String
    let defaults: UserDefaults
    let suiteName: String
    let directory: URL
    let secondDirectory: URL

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.removeItem(at: secondDirectory)
    }
}
