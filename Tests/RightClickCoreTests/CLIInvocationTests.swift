import Foundation
import Testing
@testable import RightClickCore

struct CLIInvocationTests {
    @Test
    func deepLinkRoundTripsSpecialCharacters() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "Alice's 项目-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let invocation = CLIInvocation(
            command: .codex,
            workingDirectory: directory
        )

        let deepLink = try #require(invocation.deepLink)
        #expect(CLIInvocation(deepLink: deepLink) == invocation)
    }

    @Test
    func authenticatedDeepLinkRoundTrips() throws {
        let token = ExtensionRequestTokenStore.makeToken()
        let invocation = CLIInvocation(
            command: .claude,
            workingDirectory: FileManager.default.temporaryDirectory,
            authenticationToken: token
        )

        let deepLink = try #require(invocation.deepLink)
        #expect(CLIInvocation(deepLink: deepLink) == invocation)
    }

    @Test
    func rejectsUnrelatedURL() {
        let url = URL(string: "https://example.com")!
        #expect(CLIInvocation(deepLink: url) == nil)
    }

    @Test
    func rejectsUnknownOrDuplicatedParameters() {
        let unknown = URL(
            string: "rightclick://run?tool=codex&cwd=/tmp&command=whoami"
        )!
        let duplicated = URL(
            string: "rightclick://run?tool=codex&tool=claude&cwd=/tmp"
        )!

        #expect(CLIInvocation(deepLink: unknown) == nil)
        #expect(CLIInvocation(deepLink: duplicated) == nil)
    }

    @Test
    func rejectsMalformedAuthenticationToken() {
        let malformed = URL(
            string: "rightclick://run?tool=codex&cwd=/tmp&token=guess"
        )!

        #expect(CLIInvocation(deepLink: malformed) == nil)
    }

    @Test
    func rejectsRelativeMissingAndFilePaths() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let relative = URL(string: "rightclick://run?tool=codex&cwd=tmp")!
        let missing = URL(
            string: "rightclick://run?tool=codex&cwd=/definitely/missing/rightclick"
        )!
        var components = URLComponents()
        components.scheme = "rightclick"
        components.host = "run"
        components.queryItems = [
            URLQueryItem(name: "tool", value: "codex"),
            URLQueryItem(name: "cwd", value: file.path)
        ]

        #expect(CLIInvocation(deepLink: relative) == nil)
        #expect(CLIInvocation(deepLink: missing) == nil)
        #expect(CLIInvocation(deepLink: components.url!) == nil)
    }
}
