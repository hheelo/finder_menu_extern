import Foundation
import Testing
@testable import RightClickCore

struct TerminalInvocationTests {
    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "终端 Alice's-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    @Test
    func roundTripsDirectoryWithSpecialCharacters() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let invocation = TerminalInvocation(workingDirectory: directory)
        let deepLink = try #require(invocation.deepLink)
        let parsed = try #require(TerminalInvocation(deepLink: deepLink))

        #expect(parsed.workingDirectory.path == directory.path)
    }

    @Test
    func rejectsFilesRelativeAndMissingPaths() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        var components = URLComponents()
        components.scheme = "rightclick"
        components.host = "terminal"
        components.queryItems = [URLQueryItem(name: "cwd", value: file.path)]

        #expect(TerminalInvocation(deepLink: components.url!) == nil)
        #expect(
            TerminalInvocation(
                deepLink: URL(string: "rightclick://terminal?cwd=tmp")!
            ) == nil
        )
        #expect(
            TerminalInvocation(
                deepLink: URL(string: "rightclick://terminal?cwd=/definitely/absent")!
            ) == nil
        )
        #expect(
            TerminalInvocation(
                deepLink: URL(string: "rightclick://terminal")!
            ) == nil
        )
    }

    @Test
    func rejectsExtraParametersAndForeignHosts() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let extra = URL(
            string: "rightclick://terminal?cwd=/tmp&app=iterm"
        )!
        let duplicated = URL(
            string: "rightclick://terminal?cwd=/tmp&cwd=/var"
        )!
        let wrongHost = URL(string: "rightclick://shell?cwd=/tmp")!
        let foreignScheme = URL(string: "https://example.com/terminal?cwd=/tmp")!

        #expect(TerminalInvocation(deepLink: extra) == nil)
        #expect(TerminalInvocation(deepLink: duplicated) == nil)
        #expect(TerminalInvocation(deepLink: wrongHost) == nil)
        #expect(TerminalInvocation(deepLink: foreignScheme) == nil)
    }

    /// 三种深链必须互不误认，否则宿主会把请求派给错误的处理分支。
    @Test
    func doesNotCollideWithOtherDeepLinks() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let terminal = try #require(
            TerminalInvocation(workingDirectory: directory).deepLink
        )
        let cli = try #require(
            CLIInvocation(command: .codex, workingDirectory: directory).deepLink
        )
        let open = try #require(
            OpenInvocation(application: .iTerm, targets: [directory]).deepLink
        )

        #expect(CLIInvocation(deepLink: terminal) == nil)
        #expect(OpenInvocation(deepLink: terminal) == nil)
        #expect(TerminalInvocation(deepLink: cli) == nil)
        #expect(TerminalInvocation(deepLink: open) == nil)
    }
}
