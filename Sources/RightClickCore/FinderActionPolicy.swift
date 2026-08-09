import Foundation

public enum FinderActionError: LocalizedError, Equatable {
    case invalidTarget
    case invalidWorkingDirectory
    case tooManyOpenTargets(count: Int, maximum: Int)
    case authenticationUnavailable
    case hostApplicationUnavailable

    public var errorDescription: String? {
        switch self {
        case .invalidTarget:
            "所选项目无法作为打开目标。"
        case .invalidWorkingDirectory:
            "无法确定有效的工作目录。"
        case let .tooManyOpenTargets(count, maximum):
            "一次最多打开 \(maximum) 个项目，当前选中 \(count) 个。"
        case .authenticationUnavailable:
            "无法建立 Finder 扩展与 RightClick 的安全连接。"
        case .hostApplicationUnavailable:
            "无法启动 RightClick，请确认 App 仍位于 Applications 文件夹中。"
        }
    }
}

/// Finder 扩展的纯决策层。FinderSync 只负责读系统状态和执行 AppKit 调用。
public enum FinderActionPolicy {
    public static func requiresAuthenticatedHost(
        _ action: RightClickAction
    ) -> Bool {
        switch action {
        case .copyPath, .copyFilename, .copyFileURL, .copyShellPath,
             .copyParentPath, .copyRelativePath, .createFile, .createFolder,
             .createFileFromClipboard:
            false
        case .openInVSCode, .openInCodex, .openInTerminal,
             .runCodexCLI, .runClaudeCode, .openInCursor, .openInZed,
             .openInSublimeText, .openInXcode, .openInJetBrains,
             .openInDefaultApplication:
            true
        }
    }

    public static func openTargetError(
        count: Int,
        maximum: Int = OpenInvocation.maximumTargets
    ) -> FinderActionError? {
        guard count > maximum else { return nil }
        return .tooManyOpenTargets(count: count, maximum: maximum)
    }

    /// 宿主本身无法启动时，不能再通过宿主上报，否则会递归。
    /// 其他扩展动作失败都应进入经过认证的错误通道。
    public static func shouldReportToHost(_ error: Error) -> Bool {
        (error as? FinderActionError) != .hostApplicationUnavailable
    }
}
