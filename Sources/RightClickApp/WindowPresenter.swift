import AppKit
import SwiftUI

/// 附属应用不参与常规激活，展示界面前必须显式抢一次前台，
/// 否则窗口会出现在其他应用后面，用户看不到。
@MainActor
enum WindowPresenter {
    /// 启动期收起窗口时用：本进程是否曾显式请出过窗口。
    private(set) static var isPresentationRequested = false
    private static weak var mainWindow: NSWindow?
    private static var openMainWindowAction: (() -> Void)?
    private static var openSettingsAction: (() -> Void)?

    static var hasMainWindow: Bool {
        mainWindow != nil
    }

    static func registerMainWindow(_ window: NSWindow) {
        mainWindow = window
    }

    static func bringMainWindowToFront() {
        guard let mainWindow else {
            appLogger.error("无法返回主窗口：主窗口已不存在")
            return
        }
        present(mainWindow)
    }

    @discardableResult
    static func showOrCreateMainWindow() -> Bool {
        if let mainWindow {
            present(mainWindow)
            return true
        }
        guard let openMainWindowAction else {
            appLogger.error("无法新建主窗口：窗口动作尚未注册")
            return false
        }
        notePresentationRequested()
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        openMainWindowAction()
        return true
    }

    static func showSettings() {
        guard let openSettingsAction else {
            appLogger.error("无法打开设置：设置动作尚未注册")
            return
        }
        notePresentationRequested()
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        openSettingsAction()
    }

    static func registerSceneActions(
        openMainWindow: @escaping () -> Void,
        openSettings: @escaping () -> Void
    ) {
        openMainWindowAction = openMainWindow
        openSettingsAction = openSettings
    }

    private static func present(_ window: NSWindow) {
        notePresentationRequested()
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        appLogger.notice("已请出窗口")
    }

    static func notePresentationRequested() {
        isPresentationRequested = true
    }

    /// UI 回归测试用：让设置窗口成为唯一剩余窗口，复现用户报告的 reopen 状态。
    static func closeMainWindowForUITesting() {
        guard AppEnvironment.isRunningUITests else { return }
        mainWindow?.close()
    }
}

@MainActor
private final class MainWindowTrackingView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            WindowPresenter.registerMainWindow(window)
        }
    }
}

private struct MainWindowReader: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        MainWindowTrackingView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct SceneActionsReader: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                WindowPresenter.registerSceneActions(
                    openMainWindow: { openWindow(id: AppWindow.mainID) },
                    openSettings: { openSettings() }
                )
            }
            .accessibilityHidden(true)
    }
}

struct MainWindowBackground: View {
    var body: some View {
        ZStack {
            MainWindowReader()
            SceneActionsReader()
        }
    }
}
