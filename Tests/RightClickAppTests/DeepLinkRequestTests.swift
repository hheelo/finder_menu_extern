import Foundation
import RightClickCore
import Testing

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
        let terminal = TerminalInvocation(
            workingDirectory: directory,
            authenticationToken: token
        )
        let open = OpenInvocation(
            application: .visualStudioCode,
            targets: [directory],
            authenticationToken: token
        )

        #expect(
            try DeepLinkRequest(
                deepLink: #require(cli.deepLink),
                expectedAuthenticationToken: token
            ) == .cli(cli)
        )
        #expect(
            try DeepLinkRequest(
                deepLink: #require(terminal.deepLink),
                expectedAuthenticationToken: token
            )
                == .terminal(terminal)
        )
        #expect(
            try DeepLinkRequest(
                deepLink: #require(open.deepLink),
                expectedAuthenticationToken: token
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

    @Test
    func authenticatesTerminalAndOpenWithLegacyTransition() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let expectedToken = ExtensionRequestTokenStore.makeToken()
        let wrongToken = ExtensionRequestTokenStore.makeToken()

        let legacyTerminal = TerminalInvocation(workingDirectory: directory)
        let legacyOpen = OpenInvocation(
            application: .visualStudioCode,
            targets: [directory]
        )
        #expect(
            try DeepLinkRequest(
                deepLink: #require(legacyTerminal.deepLink),
                expectedAuthenticationToken: expectedToken
            ).authentication == .legacyUnsigned
        )
        #expect(
            try DeepLinkRequest(
                deepLink: #require(legacyOpen.deepLink),
                expectedAuthenticationToken: expectedToken
            ).authentication == .legacyUnsigned
        )

        for url in [
            TerminalInvocation(
                workingDirectory: directory,
                authenticationToken: wrongToken
            ).deepLink,
            OpenInvocation(
                application: .visualStudioCode,
                targets: [directory],
                authenticationToken: wrongToken
            ).deepLink
        ] {
            do {
                _ = try DeepLinkRequest(
                    deepLink: #require(url),
                    expectedAuthenticationToken: expectedToken
                )
                Issue.record("令牌不匹配的请求本应被拒绝")
            } catch let error as DeepLinkRequestError {
                #expect(error == .invalidTerminal || error == .invalidOpen)
            }
        }
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
                expectedAuthenticationToken: authenticationToken
            )
            Issue.record("请求本应被拒绝", sourceLocation: sourceLocation)
        } catch let error as DeepLinkRequestError {
            #expect(error == expected, sourceLocation: sourceLocation)
        } catch {
            Issue.record("返回了错误的异常类型：\(error)", sourceLocation: sourceLocation)
        }
    }
}
