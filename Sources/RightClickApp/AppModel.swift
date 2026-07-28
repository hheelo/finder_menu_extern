import AppKit
import FinderSync
import RightClickCore

@MainActor
final class AppModel: ObservableObject {
    @Published var terminalProfile: TerminalProfile {
        didSet { AppSettings.shared.terminalProfile = terminalProfile }
    }
    @Published var lastStatus = "等待 Finder 操作"
    @Published var lastError: String?
    @Published private(set) var extensionEnabled = false

    private let executor = ActionExecutor()

    init() {
        terminalProfile = AppSettings.shared.terminalProfile
        refreshExtensionStatus()
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
    }

    func handle(url: URL) {
        guard let invocation = CLIInvocation(deepLink: url) else { return }

        do {
            try executor.execute(
                invocation,
                terminalProfile: terminalProfile
            )
            lastStatus = invocation.command == .codex
                ? "已启动 Codex CLI"
                : "已启动 Claude Code"
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
