import Foundation
import RightClickCore
import Testing
@testable import RightClick

@MainActor
struct AppModelTests {
    @Test
    func cliDeepLinkAlwaysWaitsForConfirmation() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }

        let invocation = CLIInvocation(
            command: .codex,
            workingDirectory: fixture.directory
        )
        fixture.model.handle(url: try #require(invocation.deepLink))

        #expect(fixture.model.pendingInvocation == invocation)
        #expect(fixture.executor.invocations.isEmpty)
        #expect(fixture.presentationCount.value == 1)
    }

    @Test
    func confirmationQueueAdvancesAfterCancelAndConfirm() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }

        let first = CLIInvocation(
            command: .codex,
            workingDirectory: fixture.directory
        )
        let second = CLIInvocation(
            command: .claude,
            workingDirectory: fixture.directory
        )
        let third = CLIInvocation(
            command: .codex,
            workingDirectory: fixture.secondDirectory
        )

        for invocation in [first, second, third] {
            fixture.model.handle(url: try #require(invocation.deepLink))
        }
        #expect(fixture.model.pendingInvocation == first)

        fixture.model.cancelPendingInvocation()
        await waitForMainQueue()
        #expect(fixture.model.pendingInvocation == second)

        fixture.model.confirmPendingInvocation()
        await waitForMainQueue()
        #expect(fixture.executor.invocations == [second])
        #expect(fixture.model.pendingInvocation == third)

        fixture.model.cancelPendingInvocation()
        await waitForMainQueue()
        #expect(fixture.model.pendingInvocation == nil)
    }

    @Test
    func invalidDeepLinkIsRejectedWithoutExecuting() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }

        fixture.model.handle(url: URL(string: "https://example.com")!)

        #expect(fixture.model.lastError?.contains("链接协议不是 rightclick") == true)
        #expect(fixture.model.pendingInvocation == nil)
        #expect(fixture.executor.invocations.isEmpty)
        #expect(fixture.presentationCount.value == 1)
    }

    private func makeFixture() throws -> Fixture {
        let suiteName = "RightClickAppTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        // 旧版本可能留下 false；安全行为不能再受这个历史值影响。
        defaults.set(false, forKey: "confirmCLIExecution")

        let directory = try makeDirectory()
        let secondDirectory = try makeDirectory()
        let executor = RecordingExecutor()
        let presentationCount = MutableCount()
        let settings = AppSettings(defaults: defaults)
        settings.terminalProfile = .terminal
        let model = AppModel(
            settings: settings,
            executor: executor,
            bringToFront: { presentationCount.value += 1 },
            performInitialRefresh: false
        )
        return Fixture(
            model: model,
            executor: executor,
            presentationCount: presentationCount,
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
private final class MutableCount {
    var value = 0
}

@MainActor
private struct Fixture {
    let model: AppModel
    let executor: RecordingExecutor
    let presentationCount: MutableCount
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
