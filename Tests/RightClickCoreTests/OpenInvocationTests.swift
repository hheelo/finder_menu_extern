import Foundation
import Testing
@testable import RightClickCore

struct OpenInvocationTests {
    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    @Test
    func roundTripsMultipleTargetsWithSpecialCharacters() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let first = root.appendingPathComponent("Alice's 项目.txt")
        let second = root.appendingPathComponent("a&b=c 文件.md")
        try Data().write(to: first)
        try Data().write(to: second)

        let invocation = OpenInvocation(
            application: .visualStudioCode,
            targets: [first, second]
        )
        let deepLink = try #require(invocation.deepLink)
        let parsed = try #require(OpenInvocation(deepLink: deepLink))

        #expect(parsed.application == .visualStudioCode)
        #expect(parsed.targets.map(\.path) == [first.path, second.path])
    }

    @Test
    func carriesEveryKnownApplication() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        for application in ExternalApplication.known {
            let deepLink = try #require(
                OpenInvocation(application: application, targets: [root])
                    .deepLink
            )
            #expect(OpenInvocation(deepLink: deepLink)?.application == application)
        }
    }

    /// 宿主只能被要求启动白名单里的 App，否则深链就成了任意程序启动器。
    @Test
    func rejectsUnknownApplication() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        var components = URLComponents()
        components.scheme = "rightclick"
        components.host = "open"
        components.queryItems = [
            URLQueryItem(name: "app", value: "/bin/sh"),
            URLQueryItem(name: "path", value: root.path)
        ]

        #expect(OpenInvocation(deepLink: components.url!) == nil)
    }

    @Test
    func rejectsMissingRelativeAndEmptyPaths() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let missing = URL(
            string: "rightclick://open?app=vscode&cwd=/tmp"
        )!
        let relative = URL(
            string: "rightclick://open?app=vscode&path=tmp"
        )!
        let absent = URL(
            string: "rightclick://open?app=vscode&path=/definitely/not/here"
        )!
        let noPath = URL(string: "rightclick://open?app=vscode")!

        #expect(OpenInvocation(deepLink: missing) == nil)
        #expect(OpenInvocation(deepLink: relative) == nil)
        #expect(OpenInvocation(deepLink: absent) == nil)
        #expect(OpenInvocation(deepLink: noPath) == nil)
    }

    @Test
    func rejectsDuplicatedAppAndForeignHosts() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let duplicated = URL(
            string: "rightclick://open?app=vscode&app=terminal&path=\(root.path)"
        )!
        let wrongHost = URL(
            string: "rightclick://run?app=vscode&path=\(root.path)"
        )!
        let foreignScheme = URL(
            string: "https://example.com/open?app=vscode&path=\(root.path)"
        )!

        #expect(OpenInvocation(deepLink: duplicated) == nil)
        #expect(OpenInvocation(deepLink: wrongHost) == nil)
        #expect(OpenInvocation(deepLink: foreignScheme) == nil)
    }

    /// 一个目标不存在就整体拒绝，不能只打开「碰巧存在」的那部分。
    @Test
    func rejectsWhenAnyTargetIsMissing() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        var components = URLComponents()
        components.scheme = "rightclick"
        components.host = "open"
        components.queryItems = [
            URLQueryItem(name: "app", value: "terminal"),
            URLQueryItem(name: "path", value: root.path),
            URLQueryItem(name: "path", value: "/definitely/not/here")
        ]

        #expect(OpenInvocation(deepLink: components.url!) == nil)
    }

    /// CLI 深链与打开深链必须互不误认。
    @Test
    func doesNotCollideWithTheCLIDeepLink() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let cli = try #require(
            CLIInvocation(command: .codex, workingDirectory: root).deepLink
        )
        let open = try #require(
            OpenInvocation(application: .terminal, targets: [root]).deepLink
        )

        #expect(OpenInvocation(deepLink: cli) == nil)
        #expect(CLIInvocation(deepLink: open) == nil)
    }

    @Test
    func rejectsMoreThanTheMaximumTargets() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let targets = (0...OpenInvocation.maximumTargets).map { index in
            root.appendingPathComponent("\(index).txt")
        }
        for target in targets {
            try Data().write(to: target)
        }

        let invocation = OpenInvocation(
            application: .visualStudioCode,
            targets: targets
        )
        #expect(invocation.deepLink == nil)

        var components = URLComponents()
        components.scheme = AppConstants.deepLinkScheme
        components.host = "open"
        components.queryItems = [
            URLQueryItem(name: "app", value: "vscode")
        ] + targets.map { URLQueryItem(name: "path", value: $0.path) }
        #expect(OpenInvocation(deepLink: try #require(components.url)) == nil)
    }
}
