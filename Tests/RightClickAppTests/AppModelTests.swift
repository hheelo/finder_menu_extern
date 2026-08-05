import Foundation
import RightClickCore
import Testing
@testable import RightClick

@MainActor
struct AppModelTests {
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
        #expect(fixture.model.lastError?.contains("CLI 请求无效") == true)
    }

    @Test
    func invalidDeepLinkIsRejectedWithoutExecuting() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }

        fixture.model.handle(url: URL(string: "https://example.com")!)
        await waitForMainQueue()

        #expect(fixture.model.lastError?.contains("链接协议不是 rightclick") == true)
        #expect(fixture.executor.invocations.isEmpty)
    }

    private func makeFixture() throws -> Fixture {
        let suiteName = "RightClickAppTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let directory = try makeDirectory()
        let secondDirectory = try makeDirectory()
        let executor = RecordingExecutor()
        let token = ExtensionRequestTokenStore.makeToken()
        let settings = AppSettings(defaults: defaults)
        settings.terminalProfile = .terminal
        let model = AppModel(
            settings: settings,
            executor: executor,
            extensionRequestToken: { token },
            performInitialRefresh: false
        )
        return Fixture(
            model: model,
            executor: executor,
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

    func execute(
        _ invocation: CLIInvocation,
        terminalProfile: TerminalProfile
    ) async throws {
        invocations.append(invocation)
    }
}

@MainActor
private struct Fixture {
    let model: AppModel
    let executor: RecordingExecutor
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
