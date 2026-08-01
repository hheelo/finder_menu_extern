import AppKit
import FinderSync
import RightClickCore
import os

@MainActor
final class AppModel: ObservableObject {
    @Published var terminalProfile: TerminalProfile {
        didSet { AppSettings.shared.terminalProfile = terminalProfile }
    }
    @Published var confirmCLIExecution: Bool {
        didSet {
            AppSettings.shared.confirmCLIExecution = confirmCLIExecution
        }
    }
    @Published var lastStatus = "等待 Finder 操作"
    @Published var lastError: String?
    @Published private(set) var extensionEnabled = false
    @Published private(set) var pendingInvocation: CLIInvocation?
    @Published private(set) var diagnostics: [DiagnosticItem] = []
    @Published private(set) var isRefreshingDiagnostics = false

    private let executor = ActionExecutor()

    init() {
        terminalProfile = AppSettings.shared.terminalProfile
        confirmCLIExecution = AppSettings.shared.confirmCLIExecution
        refreshExtensionStatus()
        Task { await refreshDiagnostics() }
    }

    func openExtensionSettings() {
        FIFinderSyncController.showExtensionManagementInterface()
    }

    func refreshExtensionStatus() {
        if #available(macOS 14.4, *) {
            extensionEnabled = FIFinderSyncController.isExtensionEnabled
        } else {
            extensionEnabled = false
        }

        if extensionEnabled {
            refreshFinderSessionIfNeeded()
        }
    }

    func handle(url: URL) {
        if let invocation = CLIInvocation(deepLink: url) {
            appLogger.notice("收到深链 类型=cli")
            handle(invocation)
            return
        }

        // 沙箱化的扩展不能启动其他 App，「用 X 打开」由宿主代为执行。
        if let invocation = OpenInvocation(deepLink: url) {
            appLogger.notice(
                "收到深链 类型=open 目标数=\(invocation.targets.count, privacy: .public)"
            )
            handle(invocation)
            return
        }

        appLogger.error("收到无法解析的深链")
        lastError = "已拒绝无效的启动链接：工作目录必须是现有文件夹。"
        WindowPresenter.bringToFront()
    }

    private func handle(_ invocation: CLIInvocation) {
        if confirmCLIExecution {
            pendingInvocation = invocation
            // 确认框挂在主窗口上；附属应用的窗口可能已被收起，必须先请回来。
            WindowPresenter.bringToFront()
        } else {
            execute(invocation)
        }
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
                self?.lastStatus = "已用 \(invocation.application.title) 打开"
            } catch {
                self?.reportOpenFailure(error.localizedDescription)
            }
        }
    }

    /// 扩展里不能弹窗（模态会堵死它的主线程），失败提示统一由宿主呈现。
    /// 宿主是附属应用，窗口平时收起，报错时必须显式请回前台。
    private func reportOpenFailure(_ message: String) {
        lastError = message
        WindowPresenter.bringToFront()
    }

    func cancelPendingInvocation() {
        pendingInvocation = nil
    }

    func confirmPendingInvocation() {
        guard let invocation = pendingInvocation else { return }
        pendingInvocation = nil
        execute(invocation)
    }

    func refreshDiagnostics() async {
        guard !isRefreshingDiagnostics else { return }
        isRefreshingDiagnostics = true
        diagnostics = await AppDiagnostics.collect(
            extensionEnabled: extensionEnabled
        )
        isRefreshingDiagnostics = false
    }

    func copyDiagnostics() {
        let report = AppDiagnostics.report(
            diagnostics,
            terminalProfile: terminalProfile,
            confirmationEnabled: confirmCLIExecution
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
                    terminalProfile: terminalProfile
                )
                lastStatus = "已启动 \(invocation.command.title)"
            } catch {
                lastError = error.localizedDescription
                WindowPresenter.bringToFront()
            }
        }
    }

    private func refreshFinderSessionIfNeeded() {
        guard let version = Self.bundleVersion,
              AppSettings.shared.finderSessionBuild != version else {
            return
        }

        // 先落标记再重启：这一步只应在每次升级后尝试一次。如果标记留到重启
        // 成功后才写，重启路径上的任何崩溃或挂起都会在下次启动时原样重演，
        // 把 App 变成永远打不开的死循环（0.2.6 就是这样）。重启真的失败时
        // 用户仍可用界面上的「重启 Finder」按钮手动重试。
        AppSettings.shared.finderSessionBuild = version
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
