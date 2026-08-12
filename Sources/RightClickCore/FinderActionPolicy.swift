import Foundation

public enum FinderActionError: LocalizedError, Equatable {
    case invalidTarget
    case invalidWorkingDirectory
    case tooManyOpenTargets(count: Int, maximum: Int)
    case authenticationUnavailable
    case configurationUnavailable
    case hostApplicationUnavailable

    public var errorDescription: String? {
        switch self {
        case .invalidTarget:
            L10n.text("error.invalid_target", fallback: "所选项目无法作为打开目标。")
        case .invalidWorkingDirectory:
            L10n.text(
                "error.invalid_working_directory",
                fallback: "无法确定有效的工作目录。"
            )
        case let .tooManyOpenTargets(count, maximum):
            L10n.format(
                "error.too_many_open_targets",
                fallback: "一次最多打开 %1$lld 个项目，当前选中 %2$lld 个。",
                Int64(maximum),
                Int64(count)
            )
        case .authenticationUnavailable:
            L10n.text(
                "error.authentication_unavailable",
                fallback: "无法建立 Finder 扩展与 RightClick 的安全连接。"
            )
        case .configurationUnavailable:
            L10n.text(
                "error.configuration_unavailable",
                fallback: "该菜单项的配置已被修改，请重新打开右键菜单。"
            )
        case .hostApplicationUnavailable:
            L10n.text(
                "error.host_unavailable",
                fallback: "无法启动 RightClick，请确认 App 仍位于 Applications 文件夹中。"
            )
        }
    }
}

/// Finder 扩展的纯决策层。FinderSync 只负责读系统状态和执行 AppKit 调用。
public enum FinderActionPolicy {
    /// 动作的额外前置条件。扩展只负责提供系统探测结果，不再自行决定什么算满足。
    public static func isSatisfied(
        _ action: RightClickAction,
        hasClipboardText: Bool
    ) -> Bool {
        switch action {
        case .createFileFromClipboard: hasClipboardText
        default: true
        }
    }

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
