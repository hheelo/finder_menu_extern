@preconcurrency import AppKit
@preconcurrency import FinderSync
import RightClickCore
import RightClickFinderAdapter
import os

/// 用 `os.Logger` 而不是 `NSLog`：`NSLog` 只写到 stderr，扩展由 launchd
/// 启动、stderr 被丢弃，`log show` 查不到，等于没有排查手段。
///
/// 统一用 `notice` 及以上级别：`info` 级别默认不落盘，事后 `log show` 查不到。
/// 排查命令：
/// `log show --last 10m --predicate 'subsystem == "com.hheelo.RightClick"'`
private let logger = Logger(
    subsystem: AppConstants.loggingSubsystem,
    category: "extension"
)
private let performanceLog = OSLog(
    subsystem: AppConstants.loggingSubsystem,
    category: "performance"
)

final class FinderSync: FIFinderSync {
    private let controller = FIFinderSyncController.default()
    private let actionLogStore = LocalActionLogStore(
        fileURL: LocalActionLogFile.extensionURL()
    )
    private let menuConfigurationCache = MenuConfigurationCache()
    private let tokenLock = NSLock()
    private var tokenAvailability = RetryableTokenAvailability()

    override init() {
        super.init()
        let paths = currentMenuConfiguration().monitoredDirectories
        controller.directoryURLs = MonitoredDirectoryPolicy.resolvedURLs(
            paths
        ) { path in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(
                atPath: path,
                isDirectory: &isDirectory
            ) && isDirectory.boolValue
        }
        logger.notice(
            "Finder 扩展已初始化 监控目录=\(self.controller.directoryURLs.count, privacy: .public)"
        )
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let signpostID = OSSignpostID(log: performanceLog)
        os_signpost(
            .begin,
            log: performanceLog,
            name: "BuildFinderMenu",
            signpostID: signpostID
        )
        defer {
            os_signpost(
                .end,
                log: performanceLog,
                name: "BuildFinderMenu",
                signpostID: signpostID
            )
        }
        guard let placement = MenuPlacement(menuKind),
              placement.providesContextActions else {
            logger.notice(
                "跳过菜单，位置=\(String(describing: menuKind), privacy: .public)"
            )
            return nil
        }

        let context = context(for: placement)
        // 原子替换 menu.json 会改变文件戳；缓存只省掉未变化配置的重复解码，
        // 设置保存后下一次右键仍会立即生效。
        let configuration = currentMenuConfiguration()
        let nodes = RightClickMenu.nodes(
            placement: placement,
            context: context,
            configuration: configuration
        )
        // 一次菜单构建只探测一次类型；即使菜单有多个分组，也不重复触碰
        // pasteboard 服务。真正内容仍只在用户点击创建动作后读取。
        let hasClipboardText = NSPasteboard.general.canReadObject(
            forClasses: [NSString.self]
        )
        guard let menu = FinderMenuRenderer.menu(
            nodes: nodes,
            placement: placement,
            hasClipboardText: hasClipboardText,
            authenticationAvailable: currentToken() != nil,
            target: self,
            action: #selector(performAction(_:))
        ) else { return nil }

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

    private func context(for placement: MenuPlacement) -> SelectionContext {
        FinderSelectionResolver.context(
            placement: placement,
            selectedURLs: controller.selectedItemURLs() ?? [],
            targetedURL: controller.targetedURL()
        )
    }

    @objc private func performAction(_ sender: NSMenuItem) {
        guard let payload = MenuItemPayload(menuTag: sender.tag) else {
            logger.error(
                "菜单项未携带可识别的动作，tag=\(sender.tag, privacy: .public)"
            )
            recordAction(
                .unknownMenuAction,
                result: .failed,
                errorCategory: .invalidRequest
            )
            return
        }
        switch payload {
        case let .configuredCLI(configured): performConfiguredCLI(configured)
        case let .customTemplate(template): performCustomTemplate(template)
        case let .action(action): perform(action)
        }
    }

    private func perform(_ payload: RightClickMenuItemPayload) {
        let action = payload.action
        // 菜单位置随 tag 一起往返。空白处和侧边栏必须继续忽略 Finder 窗口里
        // 可能残留的选区，确保动作落在鼠标实际指向的目录。
        let context = context(for: payload.placement)
        logger.notice("""
            执行动作=\(action.logDescription, privacy: .public) \
            tag=\(payload.menuTag, privacy: .public) \
            位置=\(String(describing: payload.placement), privacy: .public) \
            生效=\(context.effectiveURLs.count, privacy: .public) \
            工作目录=\(context.workingDirectory != nil, privacy: .public)
            """)
        reporting(
            LocalActionName(action),
            successResult: FinderActionPolicy.successResult(for: action),
            label: "动作执行失败"
        ) {
            try execute(action, in: context)
        }
    }

    /// 扩展里所有动作的统一失败出口。
    ///
    /// 绝不在扩展里弹模态框：`NSAlert.runModal()` 会占住扩展的主线程，而
    /// `menu(for:)` 也在主线程上，一旦弹出右键菜单就再也不出现。错误只记日志，
    /// 需要提示用户时经认证的 error 深链交给宿主 App。
    private func reporting(
        _ action: LocalActionName,
        successResult: LocalActionResult,
        label: String,
        _ body: () throws -> Void
    ) {
        recordAction(action, result: .started)
        do {
            try body()
            recordAction(action, result: successResult)
        } catch {
            recordAction(
                action,
                result: .failed,
                errorCategory: FinderActionPolicy.errorCategory(for: error)
            )
            logger.error(
                "\(label, privacy: .public)：\(error.localizedDescription, privacy: .public)"
            )
            if FinderActionPolicy.shouldReportToHost(error) {
                reportToHost(error.localizedDescription)
            }
        }
    }

    private func execute(
        _ action: RightClickAction,
        in context: SelectionContext
    ) throws {
        switch action {
        case .copyPath, .copyFilename, .copyFileURL, .copyShellPath,
             .copyParentPath, .copyRelativePath:
            // 相对路径的基准要向上探测 `.git`，只在点击时做；`menu(for:)`
            // 里的每一次文件系统访问都会变成右键菜单的弹出延迟。
            let base = action == .copyRelativePath
                ? RelativePathResolver.base(for: context)
                : nil
            guard let text = ClipboardText.text(
                for: action,
                urls: context.effectiveURLs,
                base: base,
                separator: currentMenuConfiguration().clipboardSeparator
            ) else {
                throw FinderActionError.invalidTarget
            }
            try copy(text)
        case .openInVSCode, .openInCodex, .openInCursor, .openInZed,
             .openInSublimeText, .openInXcode, .openInJetBrains,
             .openInDefaultApplication:
            guard let application = ExternalApplication.forOpenAction(action)
            else {
                throw FinderActionError.invalidTarget
            }
            try open(context.effectiveURLs, with: application)
        case let .createFile(template):
            try forwardCreation(
                .builtInTemplate(template),
                context: context,
                action: LocalActionName(action)
            )
        case .createFolder:
            try forwardCreation(
                .folder,
                context: context,
                action: .createFolder
            )
        case .createFileFromClipboard:
            try forwardCreation(
                .clipboardText,
                context: context,
                action: .createFileFromClipboard
            )
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
            openHost(with: deepLink, action: .openInTerminal)
        case .runCodexCLI:
            try openHost(for: .codex, context: context)
        case .runClaudeCode:
            try openHost(for: .claude, context: context)
        }
    }

    private func performConfiguredCLI(_ payload: ConfiguredCLIMenuItemPayload) {
        let context = context(for: payload.placement)
        reporting(
            .configuredCLI,
            successResult: .forwarded,
            label: "动态 CLI 启动失败"
        ) {
            guard let profile = currentMenuConfiguration()
                .cliProfile(forSlot: payload.menuSlot) else {
                throw FinderActionError.configurationUnavailable
            }
            guard let token = currentToken() else {
                throw FinderActionError.authenticationUnavailable
            }
            guard let directory = context.workingDirectory,
                  let deepLink = ConfiguredCLIInvocation(
                      profileID: profile.id,
                      workingDirectory: directory,
                      authenticationToken: token
                  ).deepLink else {
                throw FinderActionError.invalidWorkingDirectory
            }
            logger.notice("""
                执行动态CLI id=\(profile.id, privacy: .public) \
                slot=\(profile.menuSlot, privacy: .public)
                """)
            openHost(with: deepLink, action: .configuredCLI)
        }
    }

    private func performCustomTemplate(_ payload: CustomTemplateMenuItemPayload) {
        let context = context(for: payload.placement)
        reporting(
            .customTemplate,
            successResult: .forwarded,
            label: "自定义模板创建失败"
        ) {
            guard let template = currentMenuConfiguration()
                .customTemplate(forSlot: payload.menuSlot) else {
                throw FinderActionError.configurationUnavailable
            }
            try forwardCreation(
                .customTemplate(menuSlot: template.menuSlot),
                context: context,
                action: .customTemplate
            )
        }
    }

    private func forwardCreation(
        _ request: FileCreationInvocation.Request,
        context: SelectionContext,
        action: LocalActionName
    ) throws {
        guard let token = currentToken() else {
            throw FinderActionError.authenticationUnavailable
        }
        guard let directory = context.creationDirectory,
              let deepLink = FileCreationInvocation(
                  request: request,
                  directory: directory,
                  authenticationToken: token
              ).deepLink else {
            throw FinderActionError.invalidTarget
        }
        openHost(with: deepLink, action: action)
    }

    private func currentMenuConfiguration() -> MenuConfiguration {
        menuConfigurationCache.configuration(
            at: MenuConfigurationFile.extensionURL()
        )
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
        if let error = FinderActionPolicy.openTargetError(count: urls.count) {
            throw error
        }
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
        openHost(
            with: deepLink,
            action: LocalActionName(opening: application)
        )
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
        openHost(with: deepLink, action: LocalActionName(command))
    }

    /// 只用 `open(_ url:)` 系列：指定 App 去启动在沙箱里会被拒绝，打开 URL 不会。
    ///
    /// 关键是不要激活宿主。宿主只是代为执行动作，一旦被带到前台，
    /// 系统会把它先前收起的窗口重新显示出来——用户每点一次功能就看到窗口闪一下。
    private func openHost(
        with deepLink: URL,
        action: LocalActionName,
        kind: HostRequestKind = .action
    ) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        // completionHandler 是 @Sendable；只捕获自身已同步的日志 Store，不能把
        // FinderSync（持有 AppKit 状态、非 Sendable）整个带进回调。
        let actionLogStore = actionLogStore

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
                actionLogStore.append(LocalActionRecord(
                    source: .finderExtension,
                    action: action,
                    result: .failed,
                    errorCategory: .hostApplicationUnavailable
                ))
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
        openHost(
            with: deepLink,
            action: .extensionErrorReport,
            kind: .errorReport
        )
    }

    private func recordAction(
        _ action: LocalActionName,
        result: LocalActionResult,
        errorCategory: LocalActionErrorCategory? = nil
    ) {
        actionLogStore.append(LocalActionRecord(
            source: .finderExtension,
            action: action,
            result: result,
            errorCategory: errorCategory
        ))
    }
}

private enum HostRequestKind {
    case action
    case errorReport
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
