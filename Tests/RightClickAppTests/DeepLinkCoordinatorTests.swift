import Foundation
import RightClickCore
import Testing

@MainActor
struct DeepLinkCoordinatorTests {
    enum ExecutionRoute: CaseIterable, Sendable {
        case cli
        case terminal
        case configuredCLI

        var actionName: LocalActionName {
            switch self {
            case .cli: .runCodexCLI
            case .terminal: .openInTerminal
            case .configuredCLI: .configuredCLI
            }
        }
    }

    @Test(arguments: ExecutionRoute.allCases)
    func executionRouteSucceeds(_ route: ExecutionRoute) async throws {
        let fixture = try makeFixture(route: route)
        defer { fixture.cleanUp() }

        fixture.coordinator.dispatch(
            fixture.deepLink,
            terminalProfile: .terminal,
            terminalWindowBehavior: .newWindow,
            emit: fixture.events.append
        )
        await waitForCompletion(fixture.records)

        #expect(fixture.records.values.map(\.action) == [
            route.actionName,
            route.actionName
        ])
        #expect(fixture.records.values.map(\.result) == [
            .received,
            .succeeded
        ])
        #expect(fixture.records.values.allSatisfy {
            $0.errorCategory == nil
        })
        #expect(fixture.events.statuses.count == 2)
        #expect(fixture.events.failures.isEmpty)
        #expect(fixture.executor.calls == [route])
        #expect(fixture.executor.terminalProfiles == [.terminal])
        #expect(fixture.executor.windowBehaviors == [.newWindow])
    }

    @Test(arguments: ExecutionRoute.allCases)
    func executionRouteFailureIsReported(
        _ route: ExecutionRoute
    ) async throws {
        let failureMessage = "测试执行失败"
        let fixture = try makeFixture(
            route: route,
            failureMessage: failureMessage
        )
        defer { fixture.cleanUp() }

        fixture.coordinator.dispatch(
            fixture.deepLink,
            terminalProfile: .terminal,
            terminalWindowBehavior: .newWindow,
            emit: fixture.events.append
        )
        await waitForCompletion(fixture.records)

        #expect(fixture.records.values.map(\.action) == [
            route.actionName,
            route.actionName
        ])
        #expect(fixture.records.values.map(\.result) == [
            .received,
            .failed
        ])
        #expect(fixture.records.values.last?.errorCategory == .executionFailed)
        #expect(fixture.events.statuses.count == 1)
        #expect(fixture.events.failures == [failureMessage])
        #expect(fixture.executor.calls == [route])
    }

    private func makeFixture(
        route: ExecutionRoute,
        failureMessage: String? = nil
    ) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        let token = ExtensionRequestTokenStore.makeToken()
        let profile = CLIProfile(
            id: "test-cli",
            title: "Test CLI",
            executable: "test-cli",
            menuSlot: 1
        )
        let deepLink: URL
        switch route {
        case .cli:
            deepLink = try #require(CLIInvocation(
                command: .codex,
                workingDirectory: directory,
                authenticationToken: token
            ).deepLink)
        case .terminal:
            deepLink = try #require(TerminalInvocation(
                workingDirectory: directory,
                authenticationToken: token
            ).deepLink)
        case .configuredCLI:
            deepLink = try #require(ConfiguredCLIInvocation(
                profileID: profile.id,
                workingDirectory: directory,
                authenticationToken: token
            ).deepLink)
        }

        let executor = CoordinatorRecordingExecutor(
            failureMessage: failureMessage
        )
        let events = EventRecorder()
        let records = ActionRecordRecorder()
        let coordinator = DeepLinkCoordinator(
            extensionRequestToken: { token },
            executor: executor,
            menuConfiguration: {
                MenuConfiguration(cliProfiles: [profile])
            },
            recordAction: records.append,
            applicationURL: { _ in nil }
        )
        return Fixture(
            coordinator: coordinator,
            executor: executor,
            events: events,
            records: records,
            deepLink: deepLink,
            directory: directory
        )
    }

    private func waitForCompletion(
        _ records: ActionRecordRecorder
    ) async {
        for _ in 0..<100 where records.values.count < 2 {
            await Task.yield()
        }
    }
}

@MainActor
private final class CoordinatorRecordingExecutor: CLIExecuting {
    typealias ExecutionRoute = DeepLinkCoordinatorTests.ExecutionRoute

    private let failureMessage: String?
    private(set) var calls: [ExecutionRoute] = []
    private(set) var terminalProfiles: [TerminalProfile] = []
    private(set) var windowBehaviors: [TerminalWindowBehavior] = []

    init(failureMessage: String?) {
        self.failureMessage = failureMessage
    }

    func openDirectory(
        _ directory: URL,
        terminalProfile: TerminalProfile,
        terminalWindowBehavior: TerminalWindowBehavior
    ) async throws {
        try record(
            .terminal,
            terminalProfile: terminalProfile,
            terminalWindowBehavior: terminalWindowBehavior
        )
    }

    func execute(
        _ invocation: CLIInvocation,
        terminalProfile: TerminalProfile,
        terminalWindowBehavior: TerminalWindowBehavior
    ) async throws {
        try record(
            .cli,
            terminalProfile: terminalProfile,
            terminalWindowBehavior: terminalWindowBehavior
        )
    }

    func executeConfigured(
        _ profile: CLIProfile,
        workingDirectory: URL,
        terminalProfile: TerminalProfile,
        terminalWindowBehavior: TerminalWindowBehavior
    ) async throws {
        try record(
            .configuredCLI,
            terminalProfile: terminalProfile,
            terminalWindowBehavior: terminalWindowBehavior
        )
    }

    private func record(
        _ route: ExecutionRoute,
        terminalProfile: TerminalProfile,
        terminalWindowBehavior: TerminalWindowBehavior
    ) throws {
        calls.append(route)
        terminalProfiles.append(terminalProfile)
        windowBehaviors.append(terminalWindowBehavior)
        if let failureMessage {
            throw CoordinatorExecutionError(message: failureMessage)
        }
    }
}

private struct CoordinatorExecutionError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
private final class EventRecorder {
    private(set) var statuses: [String] = []
    private(set) var failures: [String] = []

    func append(_ event: DeepLinkEvent) {
        switch event {
        case let .status(message): statuses.append(message)
        case let .trustedFailure(message): failures.append(message)
        }
    }
}

@MainActor
private final class ActionRecordRecorder {
    struct Value {
        let action: LocalActionName
        let result: LocalActionResult
        let errorCategory: LocalActionErrorCategory?
    }

    private(set) var values: [Value] = []

    func append(
        _ action: LocalActionName,
        _ result: LocalActionResult,
        _ errorCategory: LocalActionErrorCategory?
    ) {
        values.append(Value(
            action: action,
            result: result,
            errorCategory: errorCategory
        ))
    }
}

@MainActor
private struct Fixture {
    let coordinator: DeepLinkCoordinator
    let executor: CoordinatorRecordingExecutor
    let events: EventRecorder
    let records: ActionRecordRecorder
    let deepLink: URL
    let directory: URL

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }
}
