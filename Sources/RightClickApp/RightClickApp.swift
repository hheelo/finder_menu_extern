import AppKit
import SwiftUI
import os

let appLogger = Logger(
    subsystem: "com.hheelo.RightClick",
    category: "app"
)

/// 宿主是 `LSUIElement` 附属应用：Dock 里不出现图标。
///
/// 但它仍会被扩展的深链频繁唤起（每次「用 X 打开」「运行 CLI」都要经过它），
/// 那种唤起不该弹出任何窗口。`applicationDidFinishLaunching` 的
/// `launchIsDefaultUserInfoKey` 能区分「用户双击启动」和「为处理 URL 而启动」。
///
/// 窗口只是收起而非关闭，`AppModel` 需要展示确认框或错误时能直接把它请回来。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 是否由用户自己启动（而非为处理深链）。决定要不要检查更新。
    private(set) var isUserLaunch = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        let isDefaultLaunch = notification.userInfo?[
            NSApplication.launchIsDefaultUserInfoKey
        ] as? Bool ?? true
        isUserLaunch = isDefaultLaunch
        appLogger.notice(
            "启动完成 用户主动启动=\(isDefaultLaunch, privacy: .public)"
        )
        guard !isDefaultLaunch else { return }

        // URL 事件先于本方法到达（实测如此），此时 AppModel 可能已经因为需要
        // 确认或报错而请出了窗口，那就不能再收起。另外 SwiftUI 的窗口未必在
        // 此刻就已创建，所以下一个 runloop 再收一次。
        hideWindows()
        DispatchQueue.main.async { self.hideWindows() }
    }

    private func hideWindows() {
        guard !WindowPresenter.isPresentationRequested else {
            appLogger.notice("窗口已被显式请出，跳过收起")
            return
        }
        let visible = NSApp.windows.filter { $0.isVisible }
        for window in visible {
            window.orderOut(nil)
        }
        appLogger.notice("已收起窗口 数量=\(visible.count, privacy: .public)")
    }

    /// 附属应用没有 Dock 图标，用户再次双击 App 时靠这里把窗口请回来。
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        guard !flag else { return true }
        WindowPresenter.bringToFront()
        return true
    }
}

/// 附属应用不参与常规激活，展示界面前必须显式抢一次前台，
/// 否则窗口会出现在其他应用后面，用户看不到。
@MainActor
enum WindowPresenter {
    /// 一旦请出过窗口就不再自动收起，避免与启动期的收起逻辑打架。
    private(set) static var isPresentationRequested = false

    static func bringToFront() {
        isPresentationRequested = true
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows
            .first { $0.contentViewController != nil }?
            .makeKeyAndOrderFront(nil)
        appLogger.notice("已请出窗口")
    }
}

@main
struct RightClickApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()
    @State private var updater = UpdaterController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(updater: updater)
                .environmentObject(model)
                .frame(minWidth: 640, minHeight: 440)
                .onOpenURL { model.handle(url: $0) }
                .task {
                    // 只在用户自己打开 App 时查一次；深链唤起时不查，
                    // 否则会在用户点「用 VS Code 打开」时冒出更新界面。
                    guard delegate.isUserLaunch else { return }
                    updater.checkInBackground()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        model.refreshExtensionStatus()
                        Task { await model.refreshDiagnostics() }
                    }
                }
        }
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environmentObject(model)
                .frame(width: 560, height: 520)
        }
    }
}
