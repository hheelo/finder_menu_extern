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
    private let tokenLock = NSLock()
    private var tokenAvailability = RetryableTokenAvailability()

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
            menu.addItem(item(for: node, placement: placement))
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
    private func item(
        for node: RightClickMenuNode,
        placement: MenuPlacement
    ) -> NSMenuItem {
        switch node {
        case .separator:
            return .separator()
        case let .action(action, isEnabled):
            return actionItem(
                action,
                placement: placement,
                isEnabled: isEnabled
            )
        case let .submenu(title, isEnabled, items):
            let root = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = Self.makeMenu(title: title)
            for child in items {
                submenu.addItem(item(for: child, placement: placement))
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

    private func actionItem(
        _ action: RightClickAction,
        placement: MenuPlacement,
        isEnabled: Bool = true
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: action.title,
            action: #selector(performAction(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.tag = RightClickMenuItemPayload(
            action: action,
            placement: placement
        ).menuTag
        // 宿主型动作全部依赖认证。令牌获取失败时菜单先置灰；下次构建菜单或
        // 执行动作会再次尝试，不会让一次初始化竞争锁死整个扩展进程。
        item.isEnabled = isEnabled && (
            !action.requiresAuthenticatedHost || currentToken() != nil
        )
        return item
    }

    @objc private func performAction(_ sender: NSMenuItem) {
        guard let payload = RightClickMenuItemPayload(menuTag: sender.tag) else {
            logger.error(
                "菜单项未携带可识别的动作，tag=\(sender.tag, privacy: .public)"
            )
            return
        }
        let action = payload.action
        // 菜单位置随 tag 一起往返。空白处和侧边栏必须继续忽略 Finder 窗口里
        // 可能残留的选区，确保动作落在鼠标实际指向的目录。
        let context = context(for: payload.placement)
        logger.notice("""
            执行动作 tag=\(sender.tag, privacy: .public) \
            位置=\(String(describing: payload.placement), privacy: .public) \
            生效=\(context.effectiveURLs.count, privacy: .public) \
            工作目录=\(context.workingDirectory != nil, privacy: .public)
            """)
        do {
            switch action {
            case .copyPath:
                try copy(ClipboardText.paths(for: context.effectiveURLs))
            case .copyFilename:
                try copy(ClipboardText.filenames(for: context.effectiveURLs))
            case let .createFile(template):
                guard let directory = context.creationDirectory else {
                    throw FinderActionError.invalidTarget
                }
                let createdURL = try fileCreator.create(template, in: directory)
                NSWorkspace.shared.activateFileViewerSelecting([createdURL])
            case .openInVSCode:
                try open(context.effectiveURLs, with: .visualStudioCode)
            case .openInCodex:
                try open(context.effectiveURLs, with: .codex)
            case .openInTerminal:
                guard let token = currentToken() else {
                    throw FinderActionError.authenticationUnavailable
                }
                guard let directory = context.workingDirectory,
                      let deepLink = TerminalInvocation(
                          workingDirectory: directory,
                          authenticationToken: token
                      ).deepLink else {
                    throw FinderActionError.invalidWorkingDirectory
                }
                // 用哪个终端由宿主决定：扩展读不到用户设置。
                openHost(with: deepLink)
            case .runCodexCLI:
                try openHost(for: .codex, context: context)
            case .runClaudeCode:
                try openHost(for: .claude, context: context)
            }
        } catch {
            // 绝不在扩展里弹模态框：`NSAlert.runModal()` 会占住扩展的主线程，
            // 而 `menu(for:)` 也在主线程上，一旦弹出右键菜单就再也不出现。
            // 错误只记日志，需要提示用户时由宿主 App 负责。
            logger.error(
                "动作执行失败：\(error.localizedDescription, privacy: .public)"
            )
            reportToHost(error.localizedDescription)
        }
    }

    private func copy(_ value: String) throws {
        guard !value.isEmpty else {
            throw FinderActionError.invalidTarget
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    /// 交给宿主去启动目标 App。
    ///
    /// 扩展被沙箱化，`NSWorkspace.open(_:withApplicationAt:)` 会以
    /// 「杂项错误」失败（日志里可见 LaunchServices 立刻返回错误）。而打开
    /// URL 是沙箱允许的，所以统一用深链把请求交给未沙箱的宿主执行。
    private func open(
        _ urls: [URL],
        with application: ExternalApplication
    ) throws {
        guard let token = currentToken() else {
            throw FinderActionError.authenticationUnavailable
        }
        guard let deepLink = OpenInvocation(
            application: application,
            targets: urls,
            authenticationToken: token
        ).deepLink else {
            throw FinderActionError.invalidTarget
        }
        openHost(with: deepLink)
    }

    private func openHost(
        for command: CLICommand,
        context: SelectionContext
    ) throws {
        guard let requestToken = currentToken() else {
            throw FinderActionError.authenticationUnavailable
        }
        guard let directory = context.workingDirectory,
              let deepLink = CLIInvocation(
                  command: command,
                  workingDirectory: directory,
                  authenticationToken: requestToken
              ).deepLink else {
            throw FinderActionError.invalidWorkingDirectory
        }
        openHost(with: deepLink)
    }

    /// 只用 `open(_ url:)` 系列：指定 App 去启动在沙箱里会被拒绝，打开 URL 不会。
    ///
    /// 关键是不要激活宿主。宿主只是代为执行动作，一旦被带到前台，
    /// 系统会把它先前收起的窗口重新显示出来——用户每点一次功能就看到窗口闪一下。
    private func openHost(
        with deepLink: URL,
        kind: HostRequestKind = .action
    ) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false

        NSWorkspace.shared.open(
            deepLink,
            configuration: configuration
        ) { application, error in
            guard let error else {
                logger.notice("已交给宿主处理（未激活）")
                return
            }
            logger.error(
                "不激活方式唤起宿主失败，回退：\(error.localizedDescription, privacy: .public)"
            )
            // 万一带配置的调用在沙箱里被拒，退回最朴素的形式：
            // 宁可让窗口闪一下，也不能让功能失效。
            _ = application
            if !NSWorkspace.shared.open(deepLink) {
                let hostError = FinderActionError.hostApplicationUnavailable
                logger.error(
                    "\(hostError.localizedDescription, privacy: .public)"
                )
                // 宿主本身无法启动时不能再尝试通过宿主上报，否则会无限递归。
                if kind == .errorReport {
                    logger.error("错误报告无法送达宿主，仅保留扩展日志")
                }
            }
        }
    }

    /// 令牌延迟到真正需要时再取，并允许重试。
    ///
    /// init 时 Application Support 可能尚未就绪，或与另一个同时被拉起的扩展
    /// 实例争锁失败。Finder 不重启的话进程能活很久，一次失败不能永久锁死动作。
    private func currentToken() -> String? {
        tokenLock.lock()
        defer { tokenLock.unlock() }
        guard let token = tokenAvailability.current(load: {
            try ExtensionRequestTokenStore.loadOrCreateForExtension()
        }) else {
            logger.error("获取扩展请求令牌失败，本次动作不可用")
            return nil
        }
        return token
    }

    /// 错误报告本身失败时只写日志，绝不能递归上报。
    private func reportToHost(_ message: String) {
        let maximumLength = ErrorInvocation.maximumMessageLength
        let reportMessage = message.count <= maximumLength
            ? message
            : String(message.prefix(maximumLength - 1)) + "…"
        guard let token = currentToken(),
              let deepLink = ErrorInvocation(
                  message: reportMessage,
                  authenticationToken: token
              ).deepLink else {
            logger.error("无法构造经过认证的错误报告")
            return
        }
        openHost(with: deepLink, kind: .errorReport)
    }
}

private enum HostRequestKind {
    case action
    case errorReport
}

private extension RightClickAction {
    var requiresAuthenticatedHost: Bool {
        switch self {
        case .copyPath, .copyFilename, .createFile:
            false
        case .openInVSCode, .openInCodex, .openInTerminal,
             .runCodexCLI, .runClaudeCode:
            true
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
    case invalidTarget
    case invalidWorkingDirectory
    case authenticationUnavailable
    case hostApplicationUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidTarget:
            "所选项目无法作为打开目标。"
        case .invalidWorkingDirectory:
            "无法确定有效的工作目录。"
        case .authenticationUnavailable:
            "无法建立 Finder 扩展与 RightClick 的安全连接。"
        case .hostApplicationUnavailable:
            "无法启动 RightClick，请确认 App 仍位于 Applications 文件夹中。"
        }
    }
}
