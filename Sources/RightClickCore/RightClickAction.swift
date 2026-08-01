import Foundation

public enum RightClickAction: Codable, Equatable, Sendable {
    case copyPath
    case copyFilename
    case openInVSCode
    case openInCodex
    case openInTerminal(TerminalProfile)
    case runCodexCLI
    case runClaudeCode
    case createFile(FileTemplate)

    public var title: String {
        switch self {
        case .copyPath: "复制文件路径"
        case .copyFilename: "复制文件名"
        case .openInVSCode: "用 VS Code 打开"
        case .openInCodex: "用 Codex 打开"
        case let .openInTerminal(profile): "在 \(profile.title) 中打开"
        case .runCodexCLI: "在终端运行 Codex CLI"
        case .runClaudeCode: "在终端运行 Claude Code"
        case let .createFile(template): template.title
        }
    }
}

public extension RightClickAction {
    /// 所有可出现在菜单里的动作，顺序即 `menuTag` 的编码顺序。
    ///
    /// 新增动作请追加到末尾，不要插入中间：已发出的菜单项可能仍带着旧 tag。
    static let allMenuActions: [RightClickAction] =
        [.copyPath, .copyFilename, .openInVSCode, .openInCodex]
        + TerminalProfile.allCases.map { .openInTerminal($0) }
        + [.runCodexCLI, .runClaudeCode]
        + FileTemplate.allCases.map { .createFile($0) }

    /// 菜单项要跨进程送到 Finder、再把点击送回扩展，途中只有 plist 安全的值
    /// 能存活；自定义对象放进 `representedObject` 到不了对面，回调里取到的是
    /// nil，动作会被静默丢弃。因此把动作编码进 `NSMenuItem.tag`。
    ///
    /// 从 1 开始编号：`tag` 默认为 0，留给「不携带动作」。
    var menuTag: Int {
        guard let index = Self.allMenuActions.firstIndex(of: self) else {
            return 0
        }
        return index + 1
    }

    init?(menuTag: Int) {
        let index = menuTag - 1
        guard Self.allMenuActions.indices.contains(index) else { return nil }
        self = Self.allMenuActions[index]
    }
}
