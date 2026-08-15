import Foundation
import RightClickCore
import Testing

@MainActor
struct AppModelTests {
    @Test(arguments: [true, false], [true, false])
    func appPresentationVisibility(
        isUserLaunch: Bool,
        isPresentationRequested: Bool
    ) {
        #expect(
            AppPresentation.isUserVisible(
                isUserLaunch: isUserLaunch,
                isPresentationRequested: isPresentationRequested
            ) == (isUserLaunch || isPresentationRequested)
        )
    }

    @Test
    func deepLinkImmediatelyClassifiesColdLaunchAsHeadless() {
        var state = AppLaunchState()
        #expect(state.isUserLaunch)

        let wasLaunchDeepLink = state.receiveDeepLink()
        #expect(wasLaunchDeepLink)
        #expect(!state.isUserLaunch)

        state.finish(isDefaultLaunch: true)
        #expect(!state.isUserLaunch)
        #expect(state.hasFinishedLaunching)
        // 启动完成后的普通 URL 不应把既有用户会话重新分类或隐藏窗口。
        let wasPostLaunchDeepLink = state.receiveDeepLink()
        #expect(!wasPostLaunchDeepLink)
    }

    @Test
    func normalColdLaunchRemainsUserVisibleAfterClassification() {
        var state = AppLaunchState()

        state.finish(isDefaultLaunch: true)

        #expect(state.isUserLaunch)
        #expect(state.hasFinishedLaunching)
    }

    @Test(arguments: [true, false], [true, false])
    func reopenPolicy(
        hasVisibleWindows: Bool,
        hasPresentableWindow: Bool
    ) {
        let expectedAction: ReopenAction
        if hasPresentableWindow {
            expectedAction = .restoreExisting
        } else if hasVisibleWindows {
            expectedAction = .keepVisible
        } else {
            expectedAction = .createWindow
        }
        #expect(
            ReopenPolicy.action(
                hasVisibleWindows: hasVisibleWindows,
                hasPresentableWindow: hasPresentableWindow
            ) == expectedAction
        )
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
        #expect(fixture.model.lastError == nil)
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
    func movingAnActionDropsLegacyDynamicOrderIdentifiers() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        fixture.model.menuConfiguration.actionOrder = [
            "cli:legacy",
            "template:legacy"
        ]

        fixture.model.moveMenuAction(.copyFilename, by: -1)

        #expect(
            fixture.model.menuConfiguration.actionOrder.allSatisfy {
                RightClickAction(configurationID: $0) != nil
            }
        )
        #expect(
            fixture.model.menuConfiguration.actionOrder.count
                == RightClickAction.allMenuActions.count
        )
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
        #expect(fixture.model.lastError == nil)
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

        #expect(fixture.model.lastError == nil)
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
        #expect(fixture.model.lastError == "没有写入权限。")
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
        fixture.model.handle(url: try #require(second.deepLink))
        await waitForMainQueue()

        #expect(fixture.model.errorHistory.map(\.message) == ["持续失败。"])
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

    private func makeFixture() throws -> Fixture {
        let suiteName = "RightClickAppTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let directory = try makeDirectory()
        let secondDirectory = try makeDirectory()
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
