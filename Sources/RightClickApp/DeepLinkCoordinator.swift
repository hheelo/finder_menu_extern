import AppKit
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

    init(
        extensionRequestToken: @escaping @MainActor () -> String?,
        executor: any CLIExecuting,
        terminalResolver: TerminalResolver = TerminalResolver(),
        nonceCache: NonceCache = NonceCache(),
        menuConfiguration: @escaping @MainActor () -> MenuConfiguration = {
            .default
        },
        applicationURL: @escaping @MainActor (ExternalApplication) -> URL?
    ) {
        self.extensionRequestToken = extensionRequestToken
        self.executor = executor
        self.terminalResolver = terminalResolver
        self.nonceCache = nonceCache
        self.menuConfiguration = menuConfiguration
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

        // 能到达分派层的请求都已通过 HMAC、时间窗口和 nonce 重放校验。
        let isAuthenticated = true

        switch request.payload {
        case let .cli(invocation):
            appLogger.notice("收到深链 类型=cli")
            // 只有诊断明确跑过且确认缺失时才拦截。没有诊断项就放行，避免
            // 缓存缺失或一次检测失败把原本能用的功能挡住。
            if commandAvailability(invocation.command) == false {
                reportFailure(
                    "未在登录 Shell 中找到 \(invocation.command.rawValue)，请先安装 \(invocation.command.title)。",
                    isAuthenticated: isAuthenticated,
                    emit: emit
                )
                return
            }
            execute(
                invocation,
                terminalProfile: terminalProfile,
                terminalWindowBehavior: terminalWindowBehavior,
                isAuthenticated: isAuthenticated,
                emit: emit
            )
        case let .configuredCLI(invocation):
            appLogger.notice(
                "收到深链 类型=configured-cli id=\(invocation.profileID, privacy: .public)"
            )
            guard let profile = menuConfiguration().cliProfiles.first(where: {
                $0.id == invocation.profileID && $0.isEnabled && $0.isValid
            }) else {
                reportFailure(
                    "CLI 配置不存在或已停用。",
                    isAuthenticated: isAuthenticated,
                    emit: emit
                )
                return
            }
            executeConfigured(
                profile,
                directory: invocation.workingDirectory,
                terminalProfile: terminalProfile,
                terminalWindowBehavior: terminalWindowBehavior,
                isAuthenticated: isAuthenticated,
                emit: emit
            )
        case let .terminal(invocation):
            appLogger.notice("收到深链 类型=terminal")
            openTerminal(
                invocation.workingDirectory,
                terminalProfile: terminalProfile,
                terminalWindowBehavior: terminalWindowBehavior,
                isAuthenticated: isAuthenticated,
                emit: emit
            )
        case let .open(invocation):
            appLogger.notice(
                "收到深链 类型=open 目标数=\(invocation.targets.count, privacy: .public)"
            )
            open(
                invocation,
                isAuthenticated: isAuthenticated,
                emit: emit
            )
        case let .error(invocation):
            appLogger.notice("收到深链 类型=error")
            emit(.trustedFailure(invocation.message))
        }
    }

    private func reject(_ reason: String) {
        // 未通过认证的输入可能来自任意网页。拒绝时若通知或写入用户可见历史，
        // 攻击者就能刷通知、伪造安全提示；这里只记日志且不包含原始 URL。
        appLogger.error("收到无法解析的深链：\(reason, privacy: .public)")
    }

    private func open(
        _ invocation: OpenInvocation,
        isAuthenticated: Bool,
        emit: @escaping @MainActor (DeepLinkEvent) -> Void
    ) {
        let workspace = NSWorkspace.shared
        if invocation.application == .systemDefault {
            emit(.status("正在用默认应用打开…"))
            let results = invocation.targets.map { workspace.open($0) }
            if results.allSatisfy({ $0 }) {
                emit(.status("已用默认应用打开"))
            } else {
                reportFailure(
                    "系统默认应用无法打开所选项目。",
                    isAuthenticated: isAuthenticated,
                    emit: emit
                )
            }
            return
        }
        guard let applicationURL = applicationURL(invocation.application) else {
            appLogger.error("目标 App 未安装")
            emit(.status("等待 Finder 操作"))
            reportFailure(
                "未找到 \(invocation.application.title)，请先安装应用。",
                isAuthenticated: isAuthenticated,
                emit: emit
            )
            return
        }

        emit(.status("正在用 \(invocation.application.title) 打开…"))
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
                emit(.status("已用 \(invocation.application.title) 打开"))
            } catch {
                reportFailure(
                    error.localizedDescription,
                    isAuthenticated: isAuthenticated,
                    emit: emit
                )
            }
        }
    }

    private func execute(
        _ invocation: CLIInvocation,
        terminalProfile: TerminalProfile,
        terminalWindowBehavior: TerminalWindowBehavior,
        isAuthenticated: Bool,
        emit: @escaping @MainActor (DeepLinkEvent) -> Void
    ) {
        emit(.status("正在启动 \(invocation.command.title)…"))
        Task {
            do {
                try await executor.execute(
                    invocation,
                    terminalProfile: terminalResolver.resolvedProfile(
                        for: terminalProfile
                    ),
                    terminalWindowBehavior: terminalWindowBehavior
                )
                appLogger.notice(
                    "CLI 启动成功 tool=\(invocation.command.rawValue, privacy: .public)"
                )
                emit(.status("已启动 \(invocation.command.title)"))
            } catch {
                appLogger.error(
                    "CLI 启动失败：\(error.localizedDescription, privacy: .public)"
                )
                reportFailure(
                    error.localizedDescription,
                    isAuthenticated: isAuthenticated,
                    emit: emit
                )
            }
        }
    }

    private func openTerminal(
        _ directory: URL,
        terminalProfile: TerminalProfile,
        terminalWindowBehavior: TerminalWindowBehavior,
        isAuthenticated: Bool,
        emit: @escaping @MainActor (DeepLinkEvent) -> Void
    ) {
        let resolved = terminalResolver.resolvedProfile(for: terminalProfile)
        emit(.status("正在用 \(resolved.title) 打开…"))
        Task {
            do {
                try await executor.openDirectory(
                    directory,
                    terminalProfile: resolved,
                    terminalWindowBehavior: terminalWindowBehavior
                )
                emit(.status("已用 \(resolved.title) 打开"))
            } catch {
                reportFailure(
                    error.localizedDescription,
                    isAuthenticated: isAuthenticated,
                    emit: emit
                )
            }
        }
    }

    private func executeConfigured(
        _ profile: CLIProfile,
        directory: URL,
        terminalProfile: TerminalProfile,
        terminalWindowBehavior: TerminalWindowBehavior,
        isAuthenticated: Bool,
        emit: @escaping @MainActor (DeepLinkEvent) -> Void
    ) {
        emit(.status("正在启动 \(profile.title)…"))
        Task {
            do {
                try await executor.executeConfigured(
                    profile,
                    workingDirectory: directory,
                    terminalProfile: terminalResolver.resolvedProfile(
                        for: terminalProfile
                    ),
                    terminalWindowBehavior: terminalWindowBehavior
                )
                emit(.status("已启动 \(profile.title)"))
            } catch {
                reportFailure(
                    error.localizedDescription,
                    isAuthenticated: isAuthenticated,
                    emit: emit
                )
            }
        }
    }

    private func reportFailure(
        _ message: String,
        isAuthenticated: Bool,
        emit: @escaping @MainActor (DeepLinkEvent) -> Void
    ) {
        if isAuthenticated {
            emit(.trustedFailure(message))
        } else {
            appLogger.error("旧版未认证请求执行失败")
        }
    }
}
