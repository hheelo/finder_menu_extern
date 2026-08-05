import Foundation
import RightClickCore
import Testing
@testable import RightClick

struct DeepLinkRequestTests {
    @Test
    func routesEverySupportedDeepLink() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let token = ExtensionRequestTokenStore.makeToken()

        let cli = CLIInvocation(
            command: .codex,
            workingDirectory: directory,
            authenticationToken: token
        )
        let terminal = TerminalInvocation(workingDirectory: directory)
        let open = OpenInvocation(
            application: .visualStudioCode,
            targets: [directory]
        )

        #expect(
            try DeepLinkRequest(
                deepLink: #require(cli.deepLink),
                expectedCLIAuthenticationToken: token
            ) == .cli(cli)
        )
        #expect(
            try DeepLinkRequest(
                deepLink: #require(terminal.deepLink),
                expectedCLIAuthenticationToken: nil
            )
                == .terminal(terminal)
        )
        #expect(
            try DeepLinkRequest(
                deepLink: #require(open.deepLink),
                expectedCLIAuthenticationToken: nil
            ) == .open(open)
        )
    }

    @Test
    func reportsRequestSpecificRejections() {
        let token = ExtensionRequestTokenStore.makeToken()
        expectRejection(
            URL(string: "https://example.com")!,
            expected: .invalidScheme,
            authenticationToken: token
        )
        expectRejection(
            URL(string: "rightclick://run?tool=other&cwd=/tmp")!,
            expected: .invalidCLI,
            authenticationToken: token
        )
        expectRejection(
            URL(string: "rightclick://terminal?cwd=relative")!,
            expected: .invalidTerminal,
            authenticationToken: token
        )
        expectRejection(
            URL(string: "rightclick://open?app=unknown&path=/tmp")!,
            expected: .invalidOpen,
            authenticationToken: token
        )
        expectRejection(
            URL(string: "rightclick://unknown")!,
            expected: .unknownAction("unknown"),
            authenticationToken: token
        )
    }

    @Test
    func rejectsUnsignedAndMismatchedCLIRequests() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let expectedToken = ExtensionRequestTokenStore.makeToken()
        let wrongToken = ExtensionRequestTokenStore.makeToken()
        let unsigned = CLIInvocation(
            command: .codex,
            workingDirectory: directory
        )
        let mismatched = CLIInvocation(
            command: .codex,
            workingDirectory: directory,
            authenticationToken: wrongToken
        )

        expectRejection(
            try #require(unsigned.deepLink),
            expected: .invalidCLI,
            authenticationToken: expectedToken
        )
        expectRejection(
            try #require(mismatched.deepLink),
            expected: .invalidCLI,
            authenticationToken: expectedToken
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

    private func expectRejection(
        _ url: URL,
        expected: DeepLinkRequestError,
        authenticationToken: String?,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        do {
            _ = try DeepLinkRequest(
                deepLink: url,
                expectedCLIAuthenticationToken: authenticationToken
            )
            Issue.record("请求本应被拒绝", sourceLocation: sourceLocation)
        } catch let error as DeepLinkRequestError {
            #expect(error == expected, sourceLocation: sourceLocation)
        } catch {
            Issue.record("返回了错误的异常类型：\(error)", sourceLocation: sourceLocation)
        }
    }
}
