import Foundation
import RightClickCore
import Testing
@testable import RightClick

struct DeepLinkRequestTests {
    @Test
    func routesEverySupportedDeepLink() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let cli = CLIInvocation(command: .codex, workingDirectory: directory)
        let terminal = TerminalInvocation(workingDirectory: directory)
        let open = OpenInvocation(
            application: .visualStudioCode,
            targets: [directory]
        )

        #expect(
            try DeepLinkRequest(deepLink: #require(cli.deepLink)) == .cli(cli)
        )
        #expect(
            try DeepLinkRequest(deepLink: #require(terminal.deepLink))
                == .terminal(terminal)
        )
        #expect(
            try DeepLinkRequest(deepLink: #require(open.deepLink)) == .open(open)
        )
    }

    @Test
    func reportsRequestSpecificRejections() {
        expectRejection(
            URL(string: "https://example.com")!,
            expected: .invalidScheme
        )
        expectRejection(
            URL(string: "rightclick://run?tool=other&cwd=/tmp")!,
            expected: .invalidCLI
        )
        expectRejection(
            URL(string: "rightclick://terminal?cwd=relative")!,
            expected: .invalidTerminal
        )
        expectRejection(
            URL(string: "rightclick://open?app=unknown&path=/tmp")!,
            expected: .invalidOpen
        )
        expectRejection(
            URL(string: "rightclick://unknown")!,
            expected: .unknownAction("unknown")
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
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        do {
            _ = try DeepLinkRequest(deepLink: url)
            Issue.record("请求本应被拒绝", sourceLocation: sourceLocation)
        } catch let error as DeepLinkRequestError {
            #expect(error == expected, sourceLocation: sourceLocation)
        } catch {
            Issue.record("返回了错误的异常类型：\(error)", sourceLocation: sourceLocation)
        }
    }
}
