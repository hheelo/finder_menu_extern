import Foundation

public enum RightClickAction: Codable, Equatable, Sendable {
    case copyPath
    case copyFilename
    case openInVSCode
    case openInCodex
    case openInTerminal
    case runCodexCLI
    case runClaudeCode
    case createFile(FileTemplate)

    public var title: String {
        switch self {
        case .copyPath: "复制文件路径"
        case .copyFilename: "复制文件名"
        case .openInVSCode: "用 VS Code 打开"
        case .openInCodex: "用 Codex 打开"
        case .openInTerminal: "在终端中打开"
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
        [.copyPath, .copyFilename, .openInVSCode, .openInCodex, .openInTerminal]
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

private extension MenuPlacement {
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
