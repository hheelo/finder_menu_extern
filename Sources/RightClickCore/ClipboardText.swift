import Foundation

public enum ClipboardText {
    public static func paths(
        for urls: [URL],
        separator: ClipboardSeparator = .newline
    ) -> String {
        urls.map(\.path).joined(separator: separator.text)
    }

    public static func filenames(
        for urls: [URL],
        separator: ClipboardSeparator = .newline
    ) -> String {
        urls.map(\.lastPathComponent).joined(separator: separator.text)
    }

    public static func fileURLs(
        for urls: [URL],
        separator: ClipboardSeparator = .newline
    ) -> String {
        urls.map { $0.standardizedFileURL.absoluteString }
            .joined(separator: separator.text)
    }

    public static func shellQuotedPaths(
        for urls: [URL],
        separator: ClipboardSeparator = .newline
    ) -> String {
        urls.map { ShellCommandBuilder.quote($0.path) }
            .joined(separator: separator.text)
    }

    public static func parentPaths(
        for urls: [URL],
        separator: ClipboardSeparator = .newline
    ) -> String {
        urls.map { $0.deletingLastPathComponent().path }
            .joined(separator: separator.text)
    }

    /// 不在 `base` 之下的项回退成绝对路径，而不是生成 `../` 形式。
    public static func relativePaths(
        for urls: [URL],
        base: URL,
        separator: ClipboardSeparator = .newline
    ) -> String {
        urls.map {
            RelativePathResolver.relativePath(of: $0, from: base) ?? $0.path
        }
        .joined(separator: separator.text)
    }

    /// 复制类动作到剪贴板文本的唯一映射。非复制动作返回 nil。
    ///
    /// 放在 Core 而不是扩展里：扩展 target 没有测试，而「哪个动作产出什么文本」
    /// 恰恰是最该被测住的部分。
    public static func text(
        for action: RightClickAction,
        urls: [URL],
        base: URL?,
        separator: ClipboardSeparator = .newline
    ) -> String? {
        switch action {
        case .copyPath:
            paths(for: urls, separator: separator)
        case .copyFilename:
            filenames(for: urls, separator: separator)
        case .copyFileURL:
            fileURLs(for: urls, separator: separator)
        case .copyShellPath:
            shellQuotedPaths(for: urls, separator: separator)
        case .copyParentPath:
            parentPaths(for: urls, separator: separator)
        case .copyRelativePath:
            // 基准解析失败时返回 nil，由调用方抛出可上报的错误；
            // 绝不能悄悄退化成绝对路径，那会让用户粘错内容还不知道。
            base.map {
                relativePaths(for: urls, base: $0, separator: separator)
            }
        case .openInVSCode, .openInCodex, .openInTerminal, .runCodexCLI,
             .runClaudeCode, .createFile, .openInCursor, .openInZed,
             .openInSublimeText, .openInXcode, .openInJetBrains,
             .openInDefaultApplication, .createFolder,
             .createFileFromClipboard:
            nil
        }
    }
}
