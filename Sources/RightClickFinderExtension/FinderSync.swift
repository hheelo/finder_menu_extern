@preconcurrency import AppKit
@preconcurrency import FinderSync
import RightClickCore
import os

/// 用 `os.Logger` 而不是 `NSLog`：`NSLog` 只写到 stderr，扩展由 launchd
/// 启动、stderr 被丢弃，`log show` 查不到，等于没有排查手段。
///
/// 统一用 `notice` 及以上级别：`info` 级别默认不落盘，事后 `log show` 查不到。
/// 排查命令：
/// `log show --last 10m --predicate 'subsystem == "com.hheelo.RightClick"'`
private let logger = Logger(
    subsystem: "com.hheelo.RightClick",
    category: "extension"
)

final class FinderSync: FIFinderSync {
    private let controller = FIFinderSyncController.default()
    private let fileCreator = FileCreator()

    override init() {
        super.init()
        controller.directoryURLs = [
            URL(fileURLWithPath: "/", isDirectory: true)
        ]
        logger.notice("Finder 扩展已初始化")
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard let placement = MenuPlacement(menuKind),
              placement.providesContextActions else {
            logger.notice(
                "跳过菜单，位置=\(String(describing: menuKind), privacy: .public)"
            )
            return nil
        }

        let context = context(for: placement)
        let nodes = RightClickMenu.nodes(
            placement: placement,
            context: context
        )
        guard !nodes.isEmpty else { return nil }

        let menu = Self.makeMenu(title: "RightClick")
        for node in nodes {
            menu.addItem(item(for: node))
        }

        // 空白处/边栏右键完全依赖 targetedURL：它一旦为 nil，选区上下文就全空，
        // 菜单虽然返回了但每一项都是灰的。把判定依据一并记下来，
        // 好区分「Finder 没调用扩展」和「调用了但拿不到目标目录」。
        logger.notice("""
            菜单已构建 位置=\(String(describing: placement), privacy: .public) \
            已选=\(context.selectedURLs.count, privacy: .public) \
            有目标=\(context.targetedURL != nil, privacy: .public) \
            生效=\(context.effectiveURLs.count, privacy: .public) \
            工作目录=\(context.workingDirectory != nil, privacy: .public) \
            新建目录=\(context.creationDirectory != nil, privacy: .public) \
            项数=\(menu.items.count, privacy: .public)
            """)
        return menu
    }

    /// `NSMenu` 默认开启 `autoenablesItems`，会按「target 是否响应 action」
    /// 重新计算启用状态，从而覆盖这里手工设置的 `isEnabled`，让本该置灰的
    /// 菜单项仍然可点。菜单全部由这里构造，统一关掉自动启用。
    private static func makeMenu(title: String) -> NSMenu {
        let menu = NSMenu(title: title)
        menu.autoenablesItems = false
        return menu
    }

    /// 把 Core 描述的菜单结构渲染成 AppKit 菜单项。
    private func item(for node: RightClickMenuNode) -> NSMenuItem {
        switch node {
        case .separator:
            return .separator()
        case let .action(action, isEnabled):
            return actionItem(action, isEnabled: isEnabled)
        case let .submenu(title, isEnabled, items):
            let root = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = Self.makeMenu(title: title)
            for child in items {
                submenu.addItem(item(for: child))
            }
            root.submenu = submenu
            root.isEnabled = isEnabled
            return root
        }
    }

    private func context(for placement: MenuPlacement) -> SelectionContext {
        SelectionContext(
            selectedURLs: placement.usesTargetedURLOnly
                ? []
                : controller.selectedItemURLs() ?? [],
            targetedURL: controller.targetedURL()
        )
    }

    /// 点击时重新读取选区。菜单项经 Finder 往返后带不回构建期的上下文，
    /// 只能在这里重新问一次控制器。空白处右键时 `selectedItemURLs` 本就为空，
    /// 会自然回落到 `targetedURL`，与构建菜单时的语义一致。
    private func currentContext() -> SelectionContext {
        SelectionContext(
            selectedURLs: controller.selectedItemURLs() ?? [],
            targetedURL: controller.targetedURL()
        )
    }

    private func actionItem(
        _ action: RightClickAction,
        isEnabled: Bool = true
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: action.title,
            action: #selector(performAction(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.tag = action.menuTag
        item.isEnabled = isEnabled
        return item
    }

    @objc private func performAction(_ sender: NSMenuItem) {
        guard let action = RightClickAction(menuTag: sender.tag) else {
            logger.error(
                "菜单项未携带可识别的动作，tag=\(sender.tag, privacy: .public)"
            )
            return
        }
        let context = currentContext()
        logger.notice("""
            执行动作 tag=\(sender.tag, privacy: .public) \
            生效=\(context.effectiveURLs.count, privacy: .public) \
            工作目录=\(context.workingDirectory != nil, privacy: .public)
            """)
        do {
            switch action {
            case .copyPath:
                copy(ClipboardText.paths(for: context.effectiveURLs))
            case .copyFilename:
                copy(ClipboardText.filenames(for: context.effectiveURLs))
            case let .createFile(template):
                guard let directory = context.creationDirectory else { return }
                let createdURL = try fileCreator.create(template, in: directory)
                NSWorkspace.shared.activateFileViewerSelecting([createdURL])
            case .openInVSCode:
                try open(context.effectiveURLs, with: .visualStudioCode)
            case .openInCodex:
                try open(context.effectiveURLs, with: .codex)
            case let .openInTerminal(profile):
                guard let directory = context.workingDirectory else {
                    throw FinderActionError.invalidWorkingDirectory
                }
                try open([directory], with: profile.application)
            case .runCodexCLI:
                try openHost(for: .codex, context: context)
            case .runClaudeCode:
                try openHost(for: .claude, context: context)
            }
        } catch {
            logger.error("动作执行失败：\(error.localizedDescription, privacy: .public)")
            Self.present(message: error.localizedDescription)
        }
    }

    private func copy(_ value: String) {
        guard !value.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func open(
        _ urls: [URL],
        with application: ExternalApplication
    ) throws {
        let workspace = NSWorkspace.shared
        guard let applicationURL = application.url(
            bundleIdentifierLookup: {
                workspace.urlForApplication(withBundleIdentifier: $0)
            }
        ) else {
            throw FinderActionError.applicationNotFound(application.title)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.open(
            urls,
            withApplicationAt: applicationURL,
            configuration: configuration
        ) { _, error in
            guard let error else { return }
            logger.error("打开应用失败：\(error.localizedDescription, privacy: .public)")
            FinderSync.present(message: error.localizedDescription)
        }
    }

    private func openHost(
        for command: CLICommand,
        context: SelectionContext
    ) throws {
        guard let directory = context.workingDirectory,
              let deepLink = CLIInvocation(
                  command: command,
                  workingDirectory: directory
              ).deepLink else {
            throw FinderActionError.invalidWorkingDirectory
        }
        let workspace = NSWorkspace.shared
        guard let hostURL = workspace.urlForApplication(toOpen: deepLink) else {
            throw FinderActionError.hostApplicationUnavailable
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        workspace.open(
            [deepLink],
            withApplicationAt: hostURL,
            configuration: configuration
        ) { _, error in
            guard let error else { return }
            logger.error("唤起宿主失败：\(error.localizedDescription, privacy: .public)")
            FinderSync.present(message: error.localizedDescription)
        }
    }

    private static func present(message: String) {
        DispatchQueue.main.async {
            NSSound.beep()
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "RightClick 操作失败"
            alert.informativeText = message
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }
}

private extension MenuPlacement {
    /// `FIMenuKind` 只在扩展里可见，映射留在这一层，Core 保持与 Finder 无关。
    init?(_ menuKind: FIMenuKind) {
        switch menuKind {
        case .contextualMenuForItems: self = .items
        case .contextualMenuForContainer: self = .container
        case .contextualMenuForSidebar: self = .sidebar
        case .toolbarItemMenu: self = .toolbar
        @unknown default: return nil
        }
    }
}

private enum FinderActionError: LocalizedError {
    case applicationNotFound(String)
    case invalidWorkingDirectory
    case hostApplicationUnavailable

    var errorDescription: String? {
        switch self {
        case let .applicationNotFound(name):
            "未找到 \(name)，请先安装应用。"
        case .invalidWorkingDirectory:
            "无法确定有效的工作目录。"
        case .hostApplicationUnavailable:
            "无法启动 RightClick，请确认 App 仍位于 Applications 文件夹中。"
        }
    }
}

