import Foundation

public enum RightClickAction: Codable, Equatable, Hashable, Sendable {
    case copyPath
    case copyFilename
    case openInVSCode
    case openInCodex
    case openInTerminal
    case runCodexCLI
    case runClaudeCode
    case createFile(FileTemplate)
    case copyFileURL
    case copyShellPath
    case copyParentPath
    case openInCursor
    case openInZed
    case openInSublimeText
    case openInXcode
    case openInJetBrains
    case openInDefaultApplication
    case createFolder
    case createFileFromClipboard
    case copyRelativePath

    public var title: String {
        switch self {
        case .copyPath: L10n.text("action.copy_path", fallback: "复制文件路径")
        case .copyFilename:
            L10n.text("action.copy_filename", fallback: "复制文件名")
        case .openInVSCode:
            L10n.text("action.open_vscode", fallback: "用 VS Code 打开")
        case .openInCodex:
            L10n.text("action.open_chatgpt", fallback: "用 ChatGPT 打开")
        case .openInTerminal:
            L10n.text("action.open_terminal", fallback: "在终端中打开")
        case .runCodexCLI:
            L10n.text("action.run_codex", fallback: "在终端运行 Codex CLI")
        case .runClaudeCode:
            L10n.text("action.run_claude", fallback: "在终端运行 Claude Code")
        case let .createFile(template): template.title
        case .copyFileURL:
            L10n.text("action.copy_file_url", fallback: "复制 file URL")
        case .copyShellPath:
            L10n.text("action.copy_shell_path", fallback: "复制 Shell 引用路径")
        case .copyParentPath:
            L10n.text("action.copy_parent_path", fallback: "复制父目录路径")
        case .openInCursor:
            L10n.text("action.open_cursor", fallback: "用 Cursor 打开")
        case .openInZed: L10n.text("action.open_zed", fallback: "用 Zed 打开")
        case .openInSublimeText:
            L10n.text("action.open_sublime", fallback: "用 Sublime Text 打开")
        case .openInXcode:
            L10n.text("action.open_xcode", fallback: "用 Xcode 打开")
        case .openInJetBrains:
            L10n.text("action.open_jetbrains", fallback: "用 JetBrains IDE 打开")
        case .openInDefaultApplication:
            L10n.text("action.open_default", fallback: "用默认应用打开")
        case .createFolder:
            L10n.text("action.create_folder", fallback: "新建文件夹")
        case .createFileFromClipboard:
            L10n.text(
                "action.create_clipboard_file",
                fallback: "从剪贴板新建文本文件"
            )
        case .copyRelativePath:
            L10n.text("action.copy_relative_path", fallback: "复制相对路径")
        }
    }

    /// 日志与诊断用的稳定英文标识。不使用 `title`：UI 文案会修改、
    /// 也将被本地化，历史日志不应因翻译而无法检索。
    public var logDescription: String {
        switch self {
        case .copyPath: "copyPath"
        case .copyFilename: "copyFilename"
        case .openInVSCode: "openInVSCode"
        case .openInCodex: "openInCodex"
        case .openInTerminal: "openInTerminal"
        case .runCodexCLI: "runCodexCLI"
        case .runClaudeCode: "runClaudeCode"
        case let .createFile(template):
            "createFile(\(template.rawValue))"
        case .copyFileURL: "copyFileURL"
        case .copyShellPath: "copyShellPath"
        case .copyParentPath: "copyParentPath"
        case .openInCursor: "openInCursor"
        case .openInZed: "openInZed"
        case .openInSublimeText: "openInSublimeText"
        case .openInXcode: "openInXcode"
        case .openInJetBrains: "openInJetBrains"
        case .openInDefaultApplication: "openInDefaultApplication"
        case .createFolder: "createFolder"
        case .createFileFromClipboard: "createFileFromClipboard"
        case .copyRelativePath: "copyRelativePath"
        }
    }

    /// Finder 菜单使用的稳定 SF Symbol。扩展只负责渲染，不根据
    /// 本地化后的标题猜图标，否则切换语言会改变行为。
    public var systemImageName: String {
        switch self {
        case .copyPath, .copyFilename, .copyRelativePath,
             .copyFileURL, .copyShellPath, .copyParentPath:
            "doc.on.doc"
        case .openInVSCode, .openInCodex, .openInCursor, .openInZed,
             .openInSublimeText, .openInXcode, .openInJetBrains,
             .openInDefaultApplication:
            "square.and.arrow.up"
        case .openInTerminal:
            "terminal"
        case .runCodexCLI, .runClaudeCode:
            "terminal.fill"
        case .createFile:
            "doc.badge.plus"
        case .createFolder:
            "folder.badge.plus"
        case .createFileFromClipboard:
            "doc.on.clipboard"
        }
    }

    /// 菜单配置文件使用的稳定标识。它与 `menuTag` 分离：用户排序不能改变
    /// 已发布的跨进程整数编码。
    public var configurationID: String { logDescription }
}

public extension RightClickAction {
    /// 所有可出现在菜单里的动作，顺序即 `menuTag` 的编码顺序。
    ///
    /// 新增动作请追加到末尾，不要插入中间：已发出的菜单项可能仍带着旧 tag。
    /// 分段追加而不是写成一串 `+`：拼到这个长度后 Swift 6 的类型检查器会超时
    /// （Xcode 16.4 实测报 "unable to type-check this expression in reasonable
    /// time"）。拆开只是为了让编译器过得去，顺序与结果完全不变。
    static let allMenuActions: [RightClickAction] = {
        var actions: [RightClickAction] = [
            .copyPath, .copyFilename, .openInVSCode, .openInCodex,
            .openInTerminal, .runCodexCLI, .runClaudeCode
        ]
        actions.append(
            contentsOf: FileTemplate.allCases.map {
                RightClickAction.createFile($0)
            }
        )
        // 以下每一段都必须追加，不能插入前面：已发出的菜单 tag 是跨进程契约。
        actions.append(
            contentsOf: [.copyFileURL, .copyShellPath, .copyParentPath]
        )
        actions.append(contentsOf: [
            .openInCursor, .openInZed, .openInSublimeText, .openInXcode,
            .openInJetBrains, .openInDefaultApplication
        ])
        actions.append(contentsOf: [.createFolder, .createFileFromClipboard])
        actions.append(.copyRelativePath)
        return actions
    }()

    private static let menuTagByAction = Dictionary(
        uniqueKeysWithValues: allMenuActions.enumerated().map {
            ($0.element, $0.offset + 1)
        }
    )

    private static let actionByConfigurationID = Dictionary(
        uniqueKeysWithValues: allMenuActions.map {
            ($0.configurationID, $0)
        }
    )

    /// 菜单项要跨进程送到 Finder、再把点击送回扩展，途中只有 plist 安全的值
    /// 能存活；自定义对象放进 `representedObject` 到不了对面，回调里取到的是
    /// nil，动作会被静默丢弃。因此把动作编码进 `NSMenuItem.tag`。
    ///
    /// 从 1 开始编号：`tag` 默认为 0，留给「不携带动作」。
    var menuTag: Int {
        Self.menuTagByAction[self] ?? 0
    }

    init?(menuTag: Int) {
        let index = menuTag - 1
        guard Self.allMenuActions.indices.contains(index) else { return nil }
        self = Self.allMenuActions[index]
    }

    init?(configurationID: String) {
        guard let action = Self.actionByConfigurationID[configurationID] else {
            return nil
        }
        self = action
    }
}

/// Finder 把菜单项送出扩展进程、再把点击送回来时，只能可靠保留整数 tag。
/// 点击时不仅需要知道动作，还要知道菜单来自项目、空白处还是侧边栏；否则重新
/// 读取 Finder 选区时，空白处/侧边栏动作可能误用窗口里残留的旧选区。
public struct RightClickMenuItemPayload: Equatable, Sendable {
    public let action: RightClickAction
    public let placement: MenuPlacement

    private static let actionStride = 1_000

    public init(action: RightClickAction, placement: MenuPlacement) {
        self.action = action
        self.placement = placement
    }

    public var menuTag: Int {
        placement.menuTagCode * Self.actionStride + action.menuTag
    }

    public init?(menuTag: Int) {
        let placementCode = menuTag / Self.actionStride
        let actionTag = menuTag % Self.actionStride
        guard let placement = MenuPlacement(menuTagCode: placementCode),
              let action = RightClickAction(menuTag: actionTag) else {
            return nil
        }
        self.init(action: action, placement: placement)
    }
}

/// 动态 CLI 使用 501...900 的动作码，slot 持久化在 0600 配置文件中。
/// 点击时扩展按 slot 重新查配置，因此命令和参数既不进入 tag，也不进入 URL。
public struct ConfiguredCLIMenuItemPayload: Equatable, Sendable {
    public let menuSlot: Int
    public let placement: MenuPlacement

    private static let actionStride = 1_000
    private static let dynamicBase = 500

    public init(menuSlot: Int, placement: MenuPlacement) {
        self.menuSlot = menuSlot
        self.placement = placement
    }

    public var menuTag: Int {
        placement.menuTagCode * Self.actionStride
            + Self.dynamicBase + menuSlot
    }

    public init?(menuTag: Int) {
        let placementCode = menuTag / Self.actionStride
        let actionCode = menuTag % Self.actionStride
        let slot = actionCode - Self.dynamicBase
        guard CLIProfile.validMenuSlots.contains(slot),
              let placement = MenuPlacement(menuTagCode: placementCode) else {
            return nil
        }
        self.init(menuSlot: slot, placement: placement)
    }
}

/// 自定义模板使用 101...400 的动作码；文件名和内容只从 0600 镜像读取。
public struct CustomTemplateMenuItemPayload: Equatable, Sendable {
    public let menuSlot: Int
    public let placement: MenuPlacement

    private static let actionStride = 1_000
    private static let dynamicBase = 100

    public init(menuSlot: Int, placement: MenuPlacement) {
        self.menuSlot = menuSlot
        self.placement = placement
    }

    public var menuTag: Int {
        placement.menuTagCode * Self.actionStride
            + Self.dynamicBase + menuSlot
    }

    public init?(menuTag: Int) {
        let placementCode = menuTag / Self.actionStride
        let actionCode = menuTag % Self.actionStride
        let slot = actionCode - Self.dynamicBase
        guard CustomFileTemplate.validMenuSlots.contains(slot),
              let placement = MenuPlacement(menuTagCode: placementCode) else {
            return nil
        }
        self.init(menuSlot: slot, placement: placement)
    }
}

extension MenuPlacement {
    var menuTagCode: Int {
        switch self {
        case .items: 1
        case .container: 2
        case .sidebar: 3
        case .toolbar: 4
        }
    }

    init?(menuTagCode: Int) {
        switch menuTagCode {
        case 1: self = .items
        case 2: self = .container
        case 3: self = .sidebar
        case 4: self = .toolbar
        default: return nil
        }
    }
}
