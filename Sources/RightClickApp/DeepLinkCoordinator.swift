import AppKit
import RightClickAppLogic
import RightClickCore

enum DeepLinkEvent {
    case status(String)
    case trustedFailure(String)
}

/// 深链的解析、认证与分派入口。AppModel 只发布状态并响应结果事件。
@MainActor
final class DeepLinkCoordinator {
    private let extensionRequestToken: @MainActor () -> String?
    private let executor: any CLIExecuting
    private let terminalResolver: TerminalResolver
    private let applicationURL: @MainActor (ExternalApplication) -> URL?
    private let nonceCache: NonceCache
    private let menuConfiguration: @MainActor () -> MenuConfiguration
    private let customTemplatesDirectory: @MainActor () -> URL
    private let clipboardText: @MainActor () -> String?
    private let revealCreatedItem: @MainActor (URL) -> Void
    private let fileCreator: FileCreator
    private let recordAction: @MainActor (
        LocalActionName,
        LocalActionResult,
        LocalActionErrorCategory?
    ) -> Void

    init(
        extensionRequestToken: @escaping @MainActor () -> String?,
        executor: any CLIExecuting,
        terminalResolver: TerminalResolver = TerminalResolver(),
        nonceCache: NonceCache = NonceCache(),
        menuConfiguration: @escaping @MainActor () -> MenuConfiguration = {
            .default
        },
        customTemplatesDirectory: @escaping @MainActor () -> URL = {
            MenuConfigurationFile.hostTemplatesDirectory()
        },
        clipboardText: @escaping @MainActor () -> String? = {
            NSPasteboard.general.string(forType: .string)
        },
        revealCreatedItem: @escaping @MainActor (URL) -> Void = {
            NSWorkspace.shared.activateFileViewerSelecting([$0])
        },
        fileCreator: FileCreator = FileCreator(),
        recordAction: @escaping @MainActor (
            LocalActionName,
            LocalActionResult,
            LocalActionErrorCategory?
        ) -> Void = { _, _, _ in },
        applicationURL: @escaping @MainActor (ExternalApplication) -> URL?
    ) {
        self.extensionRequestToken = extensionRequestToken
        self.executor = executor
        self.terminalResolver = terminalResolver
        self.nonceCache = nonceCache
        self.menuConfiguration = menuConfiguration
        self.customTemplatesDirectory = customTemplatesDirectory
        self.clipboardText = clipboardText
        self.revealCreatedItem = revealCreatedItem
        self.fileCreator = fileCreator
        self.recordAction = recordAction
        self.applicationURL = applicationURL
    }

    func dispatch(
        _ url: URL,
        terminalProfile: TerminalProfile,
        terminalWindowBehavior: TerminalWindowBehavior = .newTab,
        commandAvailability: (CLICommand) -> Bool? = { _ in nil },
        emit: @escaping @MainActor (DeepLinkEvent) -> Void
    ) {
        let request: DeepLinkRequest
        do {
            request = try DeepLinkRequest(
                deepLink: url,
                expectedAuthenticationToken: extensionRequestToken(),
                consumeNonce: { [nonceCache] nonce, now in
                    nonceCache.consume(nonce, now: now)
                }
            )
        } catch let error as DeepLinkRequestError {
            reject(error.rejectionReason)
            return
        } catch {
            reject("无法解析请求。")
            return
        }

        let actionName = request.payload.localActionName
        recordAction(actionName, .received, nil)
        switch request.payload {
        case let .cli(invocation):
            appLogger.notice("收到深链 类型=cli")
            // 只有诊断明确跑过且确认缺失时才拦截。没有诊断项就放行，避免
            // 缓存缺失或一次检测失败把原本能用的功能挡住。
            if commandAvailability(invocation.command) == false {
                recordAction(actionName, .failed, .commandUnavailable)
                reportFailure(
                    L10n.format(
                        "error.command_missing",
                        fallback: "未在登录 Shell 中找到 %1$@，请先安装 %2$@。",
                        invocation.command.rawValue,
                        invocation.command.title
                    ),
                    emit: emit
                )
                return
            }
            execute(
                invocation,
                terminalProfile: terminalProfile,
                terminalWindowBehavior: terminalWindowBehavior,
                emit: emit
            )
        case let .configuredCLI(invocation):
            appLogger.notice(
                "收到深链 类型=configured-cli id=\(invocation.profileID, privacy: .public)"
            )
            guard let profile = menuConfiguration().cliProfiles.first(where: {
                $0.id == invocation.profileID && $0.isEnabled && $0.isValid
            }) else {
                recordAction(actionName, .failed, .configurationUnavailable)
                reportFailure(
                    L10n.text(
                        "error.cli_configuration_missing",
                        fallback: "CLI 配置不存在或已停用。"
                    ),
                    emit: emit
                )
                return
            }
            executeConfigured(
                profile,
                directory: invocation.workingDirectory,
                terminalProfile: terminalProfile,
                terminalWindowBehavior: terminalWindowBehavior,
                emit: emit
            )
        case let .terminal(invocation):
            appLogger.notice("收到深链 类型=terminal")
            openTerminal(
                invocation.workingDirectory,
                terminalProfile: terminalProfile,
                terminalWindowBehavior: terminalWindowBehavior,
                emit: emit
            )
        case let .open(invocation):
            appLogger.notice(
                "收到深链 类型=open 目标数=\(invocation.targets.count, privacy: .public)"
            )
            open(
                invocation,
                emit: emit
            )
        case let .create(invocation):
            appLogger.notice("收到深链 类型=create")
            create(invocation, emit: emit)
        case let .error(invocation):
            appLogger.notice("收到深链 类型=error")
            recordAction(
                .extensionErrorReport,
                .failed,
                .extensionReported
            )
            emit(.trustedFailure(invocation.message))
        }
    }

    private func create(
        _ invocation: FileCreationInvocation,
        emit: @escaping @MainActor (DeepLinkEvent) -> Void
    ) {
        let actionName = invocation.request.localActionName
        emit(.status(L10n.text(
            "status.creating_item",
            fallback: "正在新建项目…"
        )))
        do {
            let createdURL: URL
            switch invocation.request {
            case let .builtInTemplate(template):
                createdURL = try fileCreator.create(
                    template,
                    override: menuConfiguration().templateOverride(
                        for: template
                    ),
                    in: invocation.directory
                )
            case .folder:
                createdURL = try fileCreator.createDirectory(
                    in: invocation.directory
                )
            case .clipboardText:
                guard let text = clipboardText(), !text.isEmpty else {
                    throw FinderActionError.invalidTarget
                }
                createdURL = try fileCreator.create(
                    contents: Data(text.utf8),
                    preferredFilename: "Untitled.txt",
                    in: invocation.directory
                )
            case let .customTemplate(menuSlot):
                guard let template = menuConfiguration()
                    .customTemplate(forSlot: menuSlot) else {
                    throw FinderActionError.configurationUnavailable
                }
                let source = customTemplatesDirectory()
                    .appendingPathComponent(template.filename)
                guard let contents = try TemplateMirror()
                    .loadContents(ofTemplateAt: source) else {
                    throw FinderActionError.configurationUnavailable
                }
                createdURL = try fileCreator.create(
                    contents: contents,
                    preferredFilename: template.filename,
                    in: invocation.directory
                )
            }
            recordAction(actionName, .succeeded, nil)
            revealCreatedItem(createdURL)
            emit(.status(L10n.text(
                "status.created_item",
                fallback: "已新建项目"
            )))
        } catch {
            recordAction(actionName, .failed, actionErrorCategory(error))
            reportFailure(error.localizedDescription, emit: emit)
        }
    }

    private func reject(_ reason: String) {
        // 未通过认证的输入可能来自任意网页。拒绝时若通知或写入用户可见历史，
        // 攻击者就能刷通知、伪造安全提示；这里只记日志且不包含原始 URL。
        // 通过认证的执行失败统一由 `reportFailure` 进入用户可见通道。
        appLogger.error("收到无法解析的深链：\(reason, privacy: .public)")
    }

    private func open(
        _ invocation: OpenInvocation,
        emit: @escaping @MainActor (DeepLinkEvent) -> Void
    ) {
        let actionName = LocalActionName(opening: invocation.application)
        let workspace = NSWorkspace.shared
        if invocation.application == .systemDefault {
            let defaultApp = L10n.text(
                "status.default_app",
                fallback: "默认应用"
            )
            emit(.status(L10n.format(
                "status.opening_with",
                fallback: "正在用 %@ 打开…",
                defaultApp
            )))
            let results = invocation.targets.map { workspace.open($0) }
            if results.allSatisfy({ $0 }) {
                recordAction(actionName, .succeeded, nil)
                emit(.status(L10n.format(
                    "status.opened_with",
                    fallback: "已用 %@ 打开",
                    defaultApp
                )))
            } else {
                recordAction(actionName, .failed, .applicationLaunchFailed)
                reportFailure(
                    L10n.text(
                        "error.default_app_open",
                        fallback: "系统默认应用无法打开所选项目。"
                    ),
                    emit: emit
                )
            }
            return
        }
        guard let applicationURL = applicationURL(invocation.application) else {
            appLogger.error("目标 App 未安装")
            recordAction(actionName, .failed, .applicationNotFound)
            emit(.status(L10n.text(
                "status.waiting",
                fallback: "等待 Finder 操作"
            )))
            reportFailure(
                L10n.format(
                    "error.application_not_found",
                    fallback: "未找到 %@，请先安装应用。",
                    invocation.application.title
                ),
                emit: emit
            )
            return
        }

        emit(.status(L10n.format(
            "status.opening_with",
            fallback: "正在用 %@ 打开…",
            invocation.application.title
        )))
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        Task {
            do {
                _ = try await workspace.open(
                    invocation.targets,
                    withApplicationAt: applicationURL,
                    configuration: configuration
                )
                appLogger.notice(
                    "打开成功 app=\(invocation.application.identifier, privacy: .public)"
                )
                recordAction(actionName, .succeeded, nil)
                emit(.status(L10n.format(
                    "status.opened_with",
                    fallback: "已用 %@ 打开",
                    invocation.application.title
                )))
            } catch {
                recordAction(actionName, .failed, .applicationLaunchFailed)
                reportFailure(
                    error.localizedDescription,
                    emit: emit
                )
            }
        }
    }

    private func execute(
        _ invocation: CLIInvocation,
        terminalProfile: TerminalProfile,
        terminalWindowBehavior: TerminalWindowBehavior,
        emit: @escaping @MainActor (DeepLinkEvent) -> Void
    ) {
        perform(
            actionName: LocalActionName(invocation.command),
            startingTitle: L10n.format(
                "status.starting",
                fallback: "正在启动 %@…",
                invocation.command.title
            ),
            startedTitle: L10n.format(
                "status.started",
                fallback: "已启动 %@",
                invocation.command.title
            ),
            emit: emit
        ) {
            do {
                try await self.executor.execute(
                    invocation,
                    terminalProfile: self.terminalResolver.resolvedProfile(
                        for: terminalProfile
                    ),
                    terminalWindowBehavior: terminalWindowBehavior
                )
                appLogger.notice(
                    "CLI 启动成功 tool=\(invocation.command.rawValue, privacy: .public)"
                )
            } catch {
                appLogger.error(
                    "CLI 启动失败：\(error.localizedDescription, privacy: .public)"
                )
                throw error
            }
        }
    }

    private func openTerminal(
        _ directory: URL,
        terminalProfile: TerminalProfile,
        terminalWindowBehavior: TerminalWindowBehavior,
        emit: @escaping @MainActor (DeepLinkEvent) -> Void
    ) {
        let resolved = terminalResolver.resolvedProfile(for: terminalProfile)
        perform(
            actionName: .openInTerminal,
            startingTitle: L10n.format(
                "status.opening_with",
                fallback: "正在用 %@ 打开…",
                resolved.title
            ),
            startedTitle: L10n.format(
                "status.opened_with",
                fallback: "已用 %@ 打开",
                resolved.title
            ),
            emit: emit
        ) {
            try await self.executor.openDirectory(
                directory,
                terminalProfile: resolved,
                terminalWindowBehavior: terminalWindowBehavior
            )
        }
    }

    private func executeConfigured(
        _ profile: CLIProfile,
        directory: URL,
        terminalProfile: TerminalProfile,
        terminalWindowBehavior: TerminalWindowBehavior,
        emit: @escaping @MainActor (DeepLinkEvent) -> Void
    ) {
        perform(
            actionName: .configuredCLI,
            startingTitle: L10n.format(
                "status.starting",
                fallback: "正在启动 %@…",
                profile.title
            ),
            startedTitle: L10n.format(
                "status.started",
                fallback: "已启动 %@",
                profile.title
            ),
            emit: emit
        ) {
            try await self.executor.executeConfigured(
                profile,
                workingDirectory: directory,
                terminalProfile: self.terminalResolver.resolvedProfile(
                    for: terminalProfile
                ),
                terminalWindowBehavior: terminalWindowBehavior
            )
        }
    }

    private func perform(
        actionName: LocalActionName,
        startingTitle: String,
        startedTitle: String,
        emit: @escaping @MainActor (DeepLinkEvent) -> Void,
        operation: @escaping @MainActor () async throws -> Void
    ) {
        emit(.status(startingTitle))
        Task {
            do {
                try await operation()
                recordAction(actionName, .succeeded, nil)
                emit(.status(startedTitle))
            } catch {
                recordAction(
                    actionName,
                    .failed,
                    actionErrorCategory(error)
                )
                reportFailure(
                    error.localizedDescription,
                    emit: emit
                )
            }
        }
    }

    /// 到达这里的 payload 都已通过 `DeepLinkRequest` 的签名、时间窗和 nonce
    /// 校验；未通过的在 `reject` 处只记安全日志，不通知也不写错误历史。因此
    /// 本层失败都来自可信请求，一律进入用户可见失败通道。
    private func reportFailure(
        _ message: String,
        emit: @escaping @MainActor (DeepLinkEvent) -> Void
    ) {
        emit(.trustedFailure(message))
    }

    private func actionErrorCategory(
        _ error: Error
    ) -> LocalActionErrorCategory {
        if let executorError = error as? ActionExecutorError {
            switch executorError {
            case .applicationNotFound: return .applicationNotFound
            case .commandUnsupported: return .unsupportedTerminal
            case .processFailed: return .executionFailed
            }
        }
        if error is CancellationError {
            return .cancelled
        }
        if error is FileCreatorError || error is CocoaError {
            return .fileSystem
        }
        if error is FinderActionError {
            return LocalActionErrorCategory(error)
        }
        return .executionFailed
    }
}

private extension DeepLinkRequest.Payload {
    var localActionName: LocalActionName {
        switch self {
        case let .cli(invocation): LocalActionName(invocation.command)
        case .configuredCLI: .configuredCLI
        case .terminal: .openInTerminal
        case let .open(invocation): LocalActionName(
            opening: invocation.application
        )
        case let .create(invocation): invocation.request.localActionName
        case .error: .extensionErrorReport
        }
    }
}

private extension FileCreationInvocation.Request {
    var localActionName: LocalActionName {
        switch self {
        case let .builtInTemplate(template):
            LocalActionName(.createFile(template))
        case .folder: .createFolder
        case .clipboardText: .createFileFromClipboard
        case .customTemplate: .customTemplate
        }
    }
}
