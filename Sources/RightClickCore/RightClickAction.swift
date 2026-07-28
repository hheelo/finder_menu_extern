import Foundation

public enum RightClickAction: Codable, Equatable, Sendable {
    case copyPath
    case copyFilename
    case openInVSCode
    case openInCodex
    case runCodexCLI
    case runClaudeCode
    case createFile(FileTemplate)

    public var title: String {
        switch self {
        case .copyPath: "复制文件路径"
        case .copyFilename: "复制文件名"
        case .openInVSCode: "用 VS Code 打开"
        case .openInCodex: "用 Codex 打开"
        case .runCodexCLI: "在终端运行 Codex CLI"
        case .runClaudeCode: "在终端运行 Claude Code"
        case let .createFile(template): template.title
        }
    }

    public var requiresHostApp: Bool {
        switch self {
        case .openInVSCode, .openInCodex, .runCodexCLI, .runClaudeCode:
            true
        case .copyPath, .copyFilename, .createFile:
            false
        }
    }
}
