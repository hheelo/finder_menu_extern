import Foundation

/// Finder 在哪种位置请求菜单。
///
/// 对应 `FIMenuKind`，但 Core 不依赖 FinderSync 框架，因此单独建模，
/// 由扩展负责把 `FIMenuKind` 映射过来。
public enum MenuPlacement: Equatable, Sendable, CaseIterable {
    /// 右键点在一个或多个项目上
    case items
    /// 右键点在窗口空白处或桌面
    case container
    /// 右键点在 Finder 边栏
    case sidebar
    /// 工具栏按钮菜单
    case toolbar

    public var providesContextActions: Bool {
        switch self {
        case .items, .container, .sidebar: true
        case .toolbar: false
        }
    }

    /// 空白处和边栏没有「所选项目」，语义上应当只看鼠标指向的目录。
    public var usesTargetedURLOnly: Bool {
        switch self {
        case .container, .sidebar: true
        case .items, .toolbar: false
        }
    }
}

/// 菜单的一个节点。菜单结构以纯数据描述，渲染成 `NSMenu` 的工作留给扩展，
/// 这样「什么位置出现哪些项、哪些该置灰」可以脱离 Finder 单独测试。
public enum RightClickMenuNode: Equatable, Sendable {
    case action(RightClickAction, isEnabled: Bool)
    case submenu(title: String, isEnabled: Bool, items: [RightClickMenuNode])
    case separator
}

public enum RightClickMenu {
    public static func nodes(
        placement: MenuPlacement,
        context: SelectionContext
    ) -> [RightClickMenuNode] {
        guard placement.providesContextActions else { return [] }

        let hasSelection = !context.effectiveURLs.isEmpty
        let hasWorkingDirectory = context.workingDirectory != nil
        let canCreateFile = context.creationDirectory != nil

        return [
            .action(.copyPath, isEnabled: hasSelection),
            .action(.copyFilename, isEnabled: hasSelection),
            .submenu(
                title: "更多复制方式",
                isEnabled: hasSelection,
                items: [
                    .action(.copyFileURL, isEnabled: hasSelection),
                    .action(.copyShellPath, isEnabled: hasSelection),
                    .action(.copyParentPath, isEnabled: hasSelection)
                ]
            ),
            .separator,
            .action(.openInVSCode, isEnabled: hasSelection),
            .action(.openInCodex, isEnabled: hasSelection),
            // 用哪个终端由宿主按用户设置解析（扩展读不到那个设置），
            // 所以这里只有一个动作，不再列出具体终端。
            .action(.openInTerminal, isEnabled: hasWorkingDirectory),
            .submenu(
                title: "运行 AI CLI",
                isEnabled: hasWorkingDirectory,
                items: [
                    .action(.runCodexCLI, isEnabled: hasWorkingDirectory),
                    .action(.runClaudeCode, isEnabled: hasWorkingDirectory)
                ]
            ),
            .separator,
            .submenu(
                title: "新建文件",
                isEnabled: canCreateFile,
                items: FileTemplate.allCases.map {
                    .action(.createFile($0), isEnabled: canCreateFile)
                }
            )
        ]
    }
}
