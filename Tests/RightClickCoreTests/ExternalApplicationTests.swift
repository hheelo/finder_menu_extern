import Foundation
import Testing
@testable import RightClickCore

struct ExternalApplicationTests {
    @Test
    func prefersBundleIdentifierLookup() {
        let expected = URL(fileURLWithPath: "/Applications/Custom.app")
        let resolved = ExternalApplication.visualStudioCode.url(
            bundleIdentifierLookup: { identifier in
                identifier == "com.microsoft.VSCode" ? expected : nil
            }
        )

        #expect(resolved == expected)
    }

    /// Terminal.app 在 /System/Applications/Utilities 下。诊断此前只搜
    /// /Applications 和 ~/Applications，与扩展的搜索路径不一致，
    /// 会报告「未找到」而菜单其实能打开。
    @Test
    func findsSystemApplicationsThroughDirectoryFallback() {
        let resolved = ExternalApplication.terminal.url(
            bundleIdentifierLookup: { _ in nil }
        )

        #expect(
            resolved?.path == "/System/Applications/Utilities/Terminal.app"
        )
    }

    @Test
    func returnsNilForAnAbsentApplication() {
        let absent = ExternalApplication(
            identifier: "nope",
            title: "Nope",
            bundleIdentifiers: ["com.example.absent"],
            names: ["Definitely Not Installed \(UUID().uuidString)"]
        )

        #expect(absent.url(bundleIdentifierLookup: { _ in nil }) == nil)
    }

    @Test
    func coversBothITermBundleNames() {
        let candidates = ExternalApplication.iTerm.candidateURLs
            .map(\.lastPathComponent)

        #expect(candidates.contains("iTerm.app"))
        #expect(candidates.contains("iTerm2.app"))
    }

    @Test
    func chatGPTKeepsThePublishedCodexIdentifier() {
        let application = ExternalApplication.codex

        #expect(application.identifier == "codex")
        #expect(application.title == "ChatGPT")
        #expect(application.bundleIdentifiers == ["com.openai.codex"])
        #expect(application.names == ["ChatGPT", "Codex"])
        #expect(ExternalApplication(identifier: "codex") == application)
    }

    @Test
    func explicitTerminalProfilesShareTheApplicationTitle() {
        #expect(TerminalProfile.terminal.title == ExternalApplication.terminal.title)
        #expect(TerminalProfile.iTerm.title == ExternalApplication.iTerm.title)
        #expect(TerminalProfile.automatic.title == "自动（优先 iTerm2）")
    }

    /// 优先 iTerm2；没装 iTerm2 时——包括用户显式选了它——都要回退到 Terminal，
    /// 否则 AppleScript 会对着不存在的应用报错。
    @Test
    func resolvesTerminalWithFallback() {
        let withITerm: (ExternalApplication) -> Bool = { _ in true }
        let withoutITerm: (ExternalApplication) -> Bool = { $0 != .iTerm }
        let withoutOptionalTerminals: (ExternalApplication) -> Bool = { _ in false }

        #expect(TerminalProfile.automatic.resolved(isInstalled: withITerm) == .iTerm)
        #expect(TerminalProfile.automatic.resolved(isInstalled: withoutITerm) == .terminal)
        #expect(TerminalProfile.iTerm.resolved(isInstalled: withoutITerm) == .terminal)
        #expect(TerminalProfile.terminal.resolved(isInstalled: withITerm) == .terminal)

        #expect(
            TerminalProfile.automatic.resolved(isInstalled: withITerm)
                .resolvedApplication == .iTerm
        )
        #expect(
            TerminalProfile.automatic.resolved(isInstalled: withoutITerm)
                .resolvedApplication == .terminal
        )

        #expect(
            TerminalProfile.warp.resolved(
                isInstalled: withoutOptionalTerminals
            ) == .terminal
        )
        #expect(TerminalProfile.wezTerm.resolved(isInstalled: { _ in true }) == .wezTerm)
        #expect(!TerminalProfile.warp.supportsCLIExecution)
        #expect(!TerminalProfile.ghostty.supportsCLIExecution)
        #expect(TerminalProfile.wezTerm.supportsCLIExecution)
        #expect(TerminalProfile.kitty.supportsCLIExecution)
    }

    @Test
    func editorAndTerminalWhitelistOnlyContainsStableUniqueIdentifiers() {
        let identifiers = ExternalApplication.known.map(\.identifier)
        #expect(Set(identifiers).count == identifiers.count)
        for application in [
            ExternalApplication.cursor, .zed, .sublimeText, .xcode,
            .jetBrains, .warp, .ghostty, .wezTerm, .kitty
        ] {
            #expect(ExternalApplication(identifier: application.identifier) == application)
        }
    }

    /// 新增一个 `openIn*` 动作却忘了接线时，这里报红；扩展 target 没有测试，
    /// 那条路径上的遗漏只能靠手点才发现。
    @Test
    func everyOpenActionMapsIntoTheWhitelist() {
        for action in RightClickAction.allMenuActions
            where action.logDescription.hasPrefix("openIn")
                && action != .openInTerminal {
            guard let application = ExternalApplication.forOpenAction(action)
            else {
                Issue.record("\(action.logDescription) 没有对应的白名单应用")
                continue
            }
            #expect(ExternalApplication.known.contains(application))
        }
        // 终端走 TerminalInvocation，不经过应用白名单。
        #expect(ExternalApplication.forOpenAction(.openInTerminal) == nil)
        #expect(ExternalApplication.forOpenAction(.copyPath) == nil)
    }
}
