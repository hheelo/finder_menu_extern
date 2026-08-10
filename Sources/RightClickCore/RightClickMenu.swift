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
    case configuredCLI(CLIProfile, isEnabled: Bool)
    case customTemplate(CustomFileTemplate, isEnabled: Bool)
    case submenu(title: String, isEnabled: Bool, items: [RightClickMenuNode])
    case separator
}

public enum RightClickMenu {
    public static func nodes(
        placement: MenuPlacement,
        context: SelectionContext,
        configuration: MenuConfiguration = .default
    ) -> [RightClickMenuNode] {
        guard placement.providesContextActions else { return [] }

        let hasSelection = !context.effectiveURLs.isEmpty
        let hasWorkingDirectory = context.workingDirectory != nil
        let canCreateFile = context.creationDirectory != nil
        let terminalSupportsCLI = configuration.terminalProfileID
            .flatMap(TerminalProfile.init(rawValue:))?
            .supportsCLIExecution ?? true
        let canRunCLI = hasWorkingDirectory && terminalSupportsCLI

        let defaultNodes: [RightClickMenuNode] = [
            .action(.copyPath, isEnabled: hasSelection),
            .action(.copyFilename, isEnabled: hasSelection),
            .submenu(
                title: L10n.text(
                    "menu.more_copy_options",
                    fallback: "更多复制方式"
                ),
                isEnabled: hasSelection,
                items: [
                    .action(.copyRelativePath, isEnabled: hasSelection),
                    .action(.copyFileURL, isEnabled: hasSelection),
                    .action(.copyShellPath, isEnabled: hasSelection),
                    .action(.copyParentPath, isEnabled: hasSelection)
                ]
            ),
            .separator,
            .action(.openInVSCode, isEnabled: hasSelection),
            .action(.openInCodex, isEnabled: hasSelection),
            .submenu(
                title: L10n.text(
                    "menu.more_editors",
                    fallback: "用其他编辑器打开"
                ),
                isEnabled: hasSelection,
                items: [
                    .action(.openInCursor, isEnabled: hasSelection),
                    .action(.openInZed, isEnabled: hasSelection),
                    .action(.openInSublimeText, isEnabled: hasSelection),
                    .action(.openInXcode, isEnabled: hasSelection),
                    .action(.openInJetBrains, isEnabled: hasSelection),
                    .action(.openInDefaultApplication, isEnabled: hasSelection)
                ]
            ),
            // 用哪个终端由宿主按用户设置解析（扩展读不到那个设置），
            // 所以这里只有一个动作，不再列出具体终端。
            .action(.openInTerminal, isEnabled: hasWorkingDirectory),
            .submenu(
                title: L10n.text("menu.run_ai_cli", fallback: "运行 AI CLI"),
                isEnabled: canRunCLI,
                items: [
                    .action(.runCodexCLI, isEnabled: canRunCLI),
                    .action(.runClaudeCode, isEnabled: canRunCLI)
                ] + configuration.cliProfiles.filter {
                    $0.isValid && $0.isEnabled
                }.map {
                    .configuredCLI($0, isEnabled: canRunCLI)
                }
            ),
            .separator,
            .submenu(
                title: L10n.text("menu.new_file", fallback: "新建文件"),
                isEnabled: canCreateFile,
                items: [
                    .action(.createFolder, isEnabled: canCreateFile),
                    .action(.createFileFromClipboard, isEnabled: canCreateFile),
                    .separator
                ] + FileTemplate.allCases.map {
                    .action(.createFile($0), isEnabled: canCreateFile)
                } + configuration.customTemplates.filter {
                    $0.isValid
                }.map {
                    .customTemplate($0, isEnabled: canCreateFile)
                }
            )
        ]
        let disabled = configuration.disabledActions
        var configured = defaultNodes.compactMap {
            filtered($0, disabledActions: disabled)
        }
        configured = removingRedundantSeparators(from: configured)
        configured = reordered(
            configured,
            actionOrder: configuration.actionOrder
        )

        guard configuration.collapseIntoSubmenu, !configured.isEmpty else {
            return configured
        }
        return [
            .submenu(
                title: "RightClick",
                isEnabled: configured.contains(where: nodeIsEnabled),
                items: configured
            )
        ]
    }

    private static func filtered(
        _ node: RightClickMenuNode,
        disabledActions: Set<String>
    ) -> RightClickMenuNode? {
        switch node {
        case .separator:
            return node
        case let .action(action, _):
            return disabledActions.contains(action.configurationID) ? nil : node
        case let .configuredCLI(profile, _):
            return profile.isEnabled && profile.isValid ? node : nil
        case let .customTemplate(template, _):
            return template.isValid ? node : nil
        case let .submenu(title, isEnabled, items):
            let children = removingRedundantSeparators(
                from: items.compactMap {
                    filtered($0, disabledActions: disabledActions)
                }
            )
            guard !children.isEmpty else { return nil }
            return .submenu(
                title: title,
                isEnabled: isEnabled && children.contains(where: nodeIsEnabled),
                items: children
            )
        }
    }

    /// 在既有分组内部排序，并用每个分组中最靠前的动作决定同段分组顺序。
    /// 不跨 separator 移动，避免动作进入语义错误的子菜单或大类。
    private static func reordered(
        _ nodes: [RightClickMenuNode],
        actionOrder: [String]
    ) -> [RightClickMenuNode] {
        // 配置文件是跨进程输入；重复 id 也必须可恢复，不能让 Finder 因
        // `Dictionary(uniqueKeysWithValues:)` 的前置条件崩溃。
        let ranks = actionOrder.enumerated().reduce(into: [String: Int]()) {
            $0[$1.element, default: $1.offset] = min(
                $0[$1.element] ?? $1.offset,
                $1.offset
            )
        }
        guard !ranks.isEmpty else { return nodes }

        let recursivelyOrdered = nodes.map { node -> RightClickMenuNode in
            guard case let .submenu(title, isEnabled, items) = node else {
                return node
            }
            return .submenu(
                title: title,
                isEnabled: isEnabled,
                items: reordered(items, actionOrder: actionOrder)
            )
        }

        var result: [RightClickMenuNode] = []
        var segment: [RightClickMenuNode] = []
        func appendSegment() {
            result.append(contentsOf: segment.enumerated().sorted { lhs, rhs in
                let leftRank = minimumRank(in: lhs.element, ranks: ranks)
                let rightRank = minimumRank(in: rhs.element, ranks: ranks)
                return leftRank == rightRank
                    ? lhs.offset < rhs.offset
                    : leftRank < rightRank
            }.map(\.element))
            segment.removeAll(keepingCapacity: true)
        }

        for node in recursivelyOrdered {
            if case .separator = node {
                appendSegment()
                result.append(node)
            } else {
                segment.append(node)
            }
        }
        appendSegment()
        return result
    }

    private static func minimumRank(
        in node: RightClickMenuNode,
        ranks: [String: Int]
    ) -> Int {
        switch node {
        case .separator:
            Int.max
        case let .action(action, _):
            ranks[action.configurationID] ?? Int.max
        case let .configuredCLI(profile, _):
            ranks[profile.configurationID] ?? Int.max
        case let .customTemplate(template, _):
            ranks[template.configurationID] ?? Int.max
        case let .submenu(_, _, items):
            items.map { minimumRank(in: $0, ranks: ranks) }.min() ?? Int.max
        }
    }

    private static func removingRedundantSeparators(
        from nodes: [RightClickMenuNode]
    ) -> [RightClickMenuNode] {
        var result: [RightClickMenuNode] = []
        for node in nodes {
            if case .separator = node,
               result.isEmpty || result.last == .separator {
                continue
            }
            result.append(node)
        }
        if result.last == .separator { result.removeLast() }
        return result
    }

    private static func nodeIsEnabled(_ node: RightClickMenuNode) -> Bool {
        switch node {
        case .separator: false
        case let .action(_, isEnabled),
             let .configuredCLI(_, isEnabled),
             let .customTemplate(_, isEnabled),
             let .submenu(_, isEnabled, _):
            isEnabled
        }
    }
}
