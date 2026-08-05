import AppKit
import FinderSync
import RightClickCore
import os

@MainActor
final class AppModel: ObservableObject {
    @Published var terminalProfile: TerminalProfile {
        didSet { settings.terminalProfile = terminalProfile }
    }
    @Published var lastStatus = "等待 Finder 操作"
    @Published var lastError: String?
    @Published private(set) var extensionEnabled = false
    @Published private(set) var diagnostics: [DiagnosticItem] = []
    @Published private(set) var isRefreshingDiagnostics = false

    private let settings: AppSettings
    private let executor: any CLIExecuting
    private let extensionRequestToken: @MainActor () -> String?

    init(
        settings: AppSettings = .shared,
        executor: any CLIExecuting = ActionExecutor(),
        extensionRequestToken: @escaping @MainActor () -> String? = {
            ExtensionRequestTokenStore.loadForHost()
        },
        performInitialRefresh: Bool = true
    ) {
        self.settings = settings
        self.executor = executor
        self.extensionRequestToken = extensionRequestToken
        terminalProfile = settings.terminalProfile

        if performInitialRefresh {
            refreshExtensionStatus()
            Task { await refreshDiagnostics() }
        }
    }

    func openExtensionSettings() {
        FIFinderSyncController.showExtensionManagementInterface()
    }

    func refreshExtensionStatus() {
        if #available(macOS 14.4, *) {
            applyExtensionStatus(
                FIFinderSyncController.isExtensionEnabled
            )
        } else {
            // 项目最低支持 14.0，而系统 API 到 14.4 才出现。旧系统通过
            // pluginkit 的用户选择标记异步判断，不能把所有用户都误报为未启用。
            Task { [weak self] in
                let enabled = await LegacyFinderExtensionStatus.isEnabled()
                self?.applyExtensionStatus(enabled)
            }
        }
    }

    private func applyExtensionStatus(_ enabled: Bool) {
        extensionEnabled = enabled
        if enabled {
            refreshFinderSessionIfNeeded()
        }
    }

    func handle(url: URL) {
        dispatch(deepLink: url)
    }

    private func dispatch(deepLink url: URL) {
        let request: DeepLinkRequest
        do {
            request = try DeepLinkRequest(
                deepLink: url,
                expectedCLIAuthenticationToken: url.host == "run"
                    ? extensionRequestToken()
                    : nil
            )
        } catch let error as DeepLinkRequestError {
            rejectDeepLink(error.rejectionReason)
            return
        } catch {
            rejectDeepLink("无法解析请求。")
            return
        }

        switch request {
        case let .cli(invocation):
            appLogger.notice("收到深链 类型=cli")
            handle(invocation)
        case let .terminal(invocation):
            // 用哪个终端由宿主解析：扩展读不到「默认终端」设置。
            appLogger.notice("收到深链 类型=terminal")
            handle(invocation)
        case let .open(invocation):
            // 沙箱化的扩展不能启动其他 App，「用 X 打开」由宿主代为执行。
            appLogger.notice(
                "收到深链 类型=open 目标数=\(invocation.targets.count, privacy: .public)"
            )
            handle(invocation)
        }
    }

    private func rejectDeepLink(_ reason: String) {
        appLogger.error("收到无法解析的深链")
        lastError = "已拒绝无效的启动链接：\(reason)"
    }

    private func handle(_ invocation: CLIInvocation) {
        // 只有持有本机扩展容器随机令牌的 Finder 请求才能到达这里。
        // 受信请求直接启动终端；宿主继续保持后台，不展示 RightClick 窗口。
        execute(invocation)
    }

    private func handle(_ invocation: OpenInvocation) {
        lastError = nil

        let workspace = NSWorkspace.shared
        guard let applicationURL = invocation.application.url(
            bundleIdentifierLookup: {
                workspace.urlForApplication(withBundleIdentifier: $0)
            }
        ) else {
            lastStatus = "等待 Finder 操作"
            appLogger.error("目标 App 未安装")
            reportOpenFailure(
                "未找到 \(invocation.application.title)，请先安装应用。"
            )
            return
        }

        lastStatus = "正在用 \(invocation.application.title) 打开…"
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        Task { [weak self] in
            do {
                _ = try await workspace.open(
                    invocation.targets,
                    withApplicationAt: applicationURL,
                    configuration: configuration
                )
                appLogger.notice(
                    "打开成功 app=\(invocation.application.identifier, privacy: .public)"
                )
                self?.lastStatus = "已用 \(invocation.application.title) 打开"
            } catch {
                self?.reportOpenFailure(error.localizedDescription)
            }
        }
    }

    private func handle(_ invocation: TerminalInvocation) {
        let application = resolvedTerminalApplication()
        handle(
            OpenInvocation(
                application: application,
                targets: [invocation.workingDirectory]
            )
        )
    }

    /// 把用户设置解析成一个确定安装了的终端。
    ///
    /// 用 `NSWorkspace.open(_:withApplicationAt:)` 打开目录，而不是走 AppleScript：
    /// 后者需要自动化权限，而「在终端中打开」本身不需要，不该为它触发授权弹窗。
    private func resolvedTerminalApplication() -> ExternalApplication {
        resolvedTerminalProfile().resolvedApplication
    }

    private func resolvedTerminalProfile() -> TerminalProfile {
        let workspace = NSWorkspace.shared
        let resolved = terminalProfile.resolved { application in
            application.url(
                bundleIdentifierLookup: {
                    workspace.urlForApplication(withBundleIdentifier: $0)
                }
            ) != nil
        }
        appLogger.notice("""
            终端已解析 设置=\(self.terminalProfile.rawValue, privacy: .public) \
            实际=\(resolved.rawValue, privacy: .public)
            """)
        return resolved
    }

    /// 扩展里不能弹窗（模态会堵死它的主线程）。错误保留在宿主状态中，
    /// 用户下次主动打开 RightClick 时可以看到；Finder 动作本身不弹宿主窗口。
    private func reportOpenFailure(_ message: String) {
        lastError = message
    }

    /// 每次刷新要起两个登录 shell，成本不低。窗口重新激活时加个节流，避免
    /// 用户在多个应用间切换时频繁重跑。
    private var lastDiagnosticsRefresh: ContinuousClock.Instant?

    func refreshDiagnostics(force: Bool = false) async {
        guard !isRefreshingDiagnostics else { return }
        if !force, let last = lastDiagnosticsRefresh,
           ContinuousClock().now - last < .seconds(30) {
            return
        }
        lastDiagnosticsRefresh = ContinuousClock().now
        isRefreshingDiagnostics = true
        let collected = await AppDiagnostics.collect(
            extensionEnabled: extensionEnabled
        )
        // 旧系统的 pluginkit 检测可能在 collect 的 await 期间返回。以完成时的
        // 最新状态改写这一行，避免设置页一直显示初始化时的 false。
        diagnostics = collected.map { item in
            guard item.id == "extension" else { return item }
            return DiagnosticItem(
                id: item.id,
                title: item.title,
                passed: extensionEnabled,
                detail: extensionEnabled ? "已启用" : "未启用"
            )
        }
        isRefreshingDiagnostics = false
    }

    func copyDiagnostics() {
        let report = AppDiagnostics.report(
            diagnostics,
            terminalProfile: terminalProfile
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        lastStatus = "诊断信息已复制"
        lastError = nil
    }

    func restartFinder() {
        restartFinder(successStatus: "Finder 已重新启动")
    }

    private func execute(_ invocation: CLIInvocation) {
        lastStatus = "正在启动 \(invocation.command.title)…"
        lastError = nil

        Task {
            do {
                try await executor.execute(
                    invocation,
                    terminalProfile: resolvedTerminalProfile()
                )
                appLogger.notice(
                    "CLI 启动成功 tool=\(invocation.command.rawValue, privacy: .public)"
                )
                lastStatus = "已启动 \(invocation.command.title)"
            } catch {
                appLogger.error(
                    "CLI 启动失败：\(error.localizedDescription, privacy: .public)"
                )
                lastError = error.localizedDescription
            }
        }
    }

    private func refreshFinderSessionIfNeeded() {
        guard let version = Self.bundleVersion,
              settings.finderSessionBuild != version else {
            return
        }

        // 先落标记再重启：这一步只应在每次升级后尝试一次。如果标记留到重启
        // 成功后才写，重启路径上的任何崩溃或挂起都会在下次启动时原样重演，
        // 把 App 变成永远打不开的死循环（0.2.6 就是这样）。重启真的失败时
        // 用户仍可用界面上的「重启 Finder」按钮手动重试。
        settings.finderSessionBuild = version
        restartFinder(successStatus: "已为当前版本重新加载 Finder")
    }

    /// 同时包含短版本号和构建号：只看 `CFBundleVersion` 的话，一旦某次发布
    /// 忘记递增构建号，升级后就不会重新加载 Finder，用户仍看到旧菜单。
    private static var bundleVersion: String? {
        let info = Bundle.main
        guard let build = info.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String else {
            return nil
        }
        let short = info.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0"
        return "\(short) (\(build))"
    }

    private func restartFinder(successStatus: String) {
        let finder = NSWorkspace.shared.runningApplications.first(
            where: { $0.bundleIdentifier == "com.apple.finder" }
        )
        if let finder, !finder.terminate() {
            lastError = "无法重启 Finder，请退出登录后重试。"
            return
        }

        lastStatus = "正在重启 Finder"
        lastError = nil

        Task { @MainActor [weak self] in
            guard let self else { return }

            if let finder {
                for _ in 0..<30 where !finder.isTerminated {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                guard finder.isTerminated else {
                    lastError = "Finder 未能退出，请退出登录后重试。"
                    return
                }
            }

            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.addsToRecentItems = false
            let finderURL = URL(
                fileURLWithPath:
                    "/System/Library/CoreServices/Finder.app",
                isDirectory: true
            )

            do {
                // 必须用 async API：completionHandler 版本的闭包会继承
                // AppModel 的 @MainActor 隔离，而 LaunchServices 在自己的
                // 队列上回调，Swift 6 的运行时隔离断言会直接让进程 SIGTRAP。
                _ = try await NSWorkspace.shared.openApplication(
                    at: finderURL,
                    configuration: configuration
                )
                lastStatus = successStatus
            } catch {
                lastError = "无法重新打开 Finder：\(error.localizedDescription)"
            }
        }
    }
}

/// macOS 14.0–14.3 的 Finder 扩展状态检测。
private enum LegacyFinderExtensionStatus {
    static func isEnabled() async -> Bool {
        await Task.detached(priority: .utility) {
            let process = Process()
            let outputPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
            process.arguments = [
                "-m", "-A", "-D", "-i",
                AppConstants.finderExtensionBundleIdentifier
            ]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = outputPipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                return false
            }

            // 查询结果很小；先读到 EOF 可避免未来 verbose 输出增大后堵住管道。
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return false }

            return AppConstants.plugInKitOutputIndicatesEnabled(
                String(decoding: data, as: UTF8.self)
            )
        }.value
    }
}
