import AppKit
import FinderSync
import RightClickCore

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
        guard let invocation = CLIInvocation(deepLink: url) else {
            lastError = "已拒绝无效的启动链接：工作目录必须是现有文件夹。"
            return
        }

        if confirmCLIExecution {
            NSApp.unhide(nil)
            NSApp.activate(ignoringOtherApps: true)
            pendingInvocation = invocation
        } else {
            NSApp.hide(nil)
            execute(invocation)
        }
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
                NSApp.unhide(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    private func refreshFinderSessionIfNeeded() {
        guard let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String,
        AppSettings.shared.finderSessionBuild != build else {
            return
        }

        restartFinder(
            successStatus: "已为当前版本重新加载 Finder"
        ) {
            AppSettings.shared.finderSessionBuild = build
        }
    }

    private func restartFinder(
        successStatus: String,
        onSuccess: @escaping @MainActor () -> Void = {}
    ) {
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
                try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<Void, Error>) in
                    NSWorkspace.shared.openApplication(
                        at: finderURL,
                        configuration: configuration
                    ) { _, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                }
                lastStatus = successStatus
                onSuccess()
            } catch {
                lastError = "无法重新打开 Finder：\(error.localizedDescription)"
            }
        }
    }
}
