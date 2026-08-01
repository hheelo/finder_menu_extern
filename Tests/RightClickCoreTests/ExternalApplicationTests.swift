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
    func terminalProfilesShareTheApplicationTitle() {
        for profile in TerminalProfile.allCases {
            #expect(profile.title == profile.application.title)
        }
        #expect(TerminalProfile.iTerm.application == .iTerm)
        #expect(TerminalProfile.terminal.application == .terminal)
    }
}
