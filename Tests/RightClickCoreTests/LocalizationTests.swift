import Testing
@testable import RightClickCore

struct LocalizationTests {
    @Test
    func resolvesEnglishAndSimplifiedChineseFromTheSharedFrameworkBundle() {
        #expect(
            L10n.text(
                "action.copy_path",
                fallback: "复制文件路径",
                localeIdentifier: "en"
            ) == "Copy File Path"
        )
        #expect(
            L10n.text(
                "action.copy_path",
                fallback: "复制文件路径",
                localeIdentifier: "zh-Hans"
            ) == "复制文件路径"
        )
        #expect(
            L10n.text(
                "action.copy_path",
                fallback: "复制文件路径",
                localeIdentifier: "en-US"
            ) == "Copy File Path"
        )
        #expect(
            L10n.text(
                "action.copy_path",
                fallback: "复制文件路径",
                localeIdentifier: "zh_CN"
            ) == "复制文件路径"
        )
    }

    @Test
    func localizedFormatsPreserveArguments() {
        #expect(
            L10n.format(
                "status.started",
                fallback: "已启动 %@",
                localeIdentifier: "en",
                "Codex CLI"
            ) == "Started Codex CLI"
        )
        #expect(
            L10n.format(
                "error.too_many_open_targets",
                fallback: "一次最多打开 %1$lld 个项目，当前选中 %2$lld 个。",
                localeIdentifier: "en-US",
                Int64(128),
                Int64(129)
            ) == "You can open up to 128 items at once; 129 are selected."
        )
    }

    @Test
    func htmlLanguageTagMatchesTheSelectedLanguage() {
        #expect(
            L10n.text(
                "html.language_tag",
                fallback: "zh-CN",
                localeIdentifier: "en"
            ) == "en"
        )
        #expect(
            L10n.text(
                "html.language_tag",
                fallback: "zh-CN",
                localeIdentifier: "zh-Hans"
            ) == "zh-CN"
        )
    }
}
