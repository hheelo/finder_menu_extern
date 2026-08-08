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

        let cliRequest = try DeepLinkRequest(
                deepLink: #require(cli.deepLink),
                expectedAuthenticationToken: token
            )
        #expect(cliRequest.payload == .cli(cli))
        #expect(cliRequest.authentication == .authenticated)

        let terminalRequest = try DeepLinkRequest(
                deepLink: #require(terminal.deepLink),
                expectedAuthenticationToken: token
            )
        #expect(terminalRequest.payload == .terminal(terminal))
        #expect(terminalRequest.authentication == .authenticated)

        let openRequest = try DeepLinkRequest(
                deepLink: #require(open.deepLink),
                expectedAuthenticationToken: token
            )
        #expect(openRequest.payload == .open(open))
        #expect(openRequest.authentication == .authenticated)
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

    @Test
    func acceptsLegacyTokenDuringUpgradeTransition() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let token = ExtensionRequestTokenStore.makeToken()
        var components = URLComponents()
        components.scheme = AppConstants.deepLinkScheme
        components.host = "run"
        components.queryItems = [
            URLQueryItem(name: "tool", value: "codex"),
            URLQueryItem(name: "cwd", value: directory.path),
            URLQueryItem(name: "token", value: token)
        ]

        let request = try DeepLinkRequest(
            deepLink: #require(components.url),
            expectedAuthenticationToken: token
        )
        #expect(request.authentication == .legacyToken)
    }

    @Test
    func rejectsReplayOfSignedRequest() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let token = ExtensionRequestTokenStore.makeToken()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let invocation = CLIInvocation(
            command: .codex,
            workingDirectory: directory,
            authenticationToken: token
        )
        let url = try #require(
            invocation.deepLink(
                now: now,
                nonce: "00000000-0000-4000-8000-000000000001"
            )
        )
        let cache = NonceCache()

        _ = try DeepLinkRequest(
            deepLink: url,
            expectedAuthenticationToken: token,
            now: now,
            consumeNonce: { cache.consume($0, now: $1) }
        )
        expectRejection(
            url,
            expected: .invalidCLI,
            authenticationToken: token,
            now: now,
            consumeNonce: { cache.consume($0, now: $1) }
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
        now: Date = Date(),
        consumeNonce: (String, Date) -> Bool = { _, _ in true },
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        do {
            _ = try DeepLinkRequest(
                deepLink: url,
                expectedAuthenticationToken: authenticationToken,
                now: now,
                consumeNonce: consumeNonce
            )
            Issue.record("请求本应被拒绝", sourceLocation: sourceLocation)
        } catch let error as DeepLinkRequestError {
            #expect(error == expected, sourceLocation: sourceLocation)
        } catch {
            Issue.record("返回了错误的异常类型：\(error)", sourceLocation: sourceLocation)
        }
    }
}
