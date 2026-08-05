import AppKit
import SwiftUI
import os

let appLogger = Logger(
    subsystem: "com.hheelo.RightClick",
    category: "app"
)

enum AppEnvironment {
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

/// 宿主是 `LSUIElement` 附属应用：Dock 里不出现图标。
///
/// 但它仍会被扩展的深链频繁唤起（每次「用 X 打开」「运行 CLI」都要经过它），
/// 那种唤起不该弹出任何窗口。`applicationDidFinishLaunching` 的
/// `launchIsDefaultUserInfoKey` 能区分「用户双击启动」和「为处理 URL 而启动」。
///
/// 窗口只是收起而非关闭，用户之后双击 App 时可以直接把它请回来。Finder 深链
/// 无论成功或失败都不主动显示宿主窗口。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 是否由用户自己启动（而非为处理深链）。决定要不要检查更新。
    private(set) var isUserLaunch = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        let isDefaultLaunch = notification.userInfo?[
            NSApplication.launchIsDefaultUserInfoKey
        ] as? Bool ?? true
        isUserLaunch = isDefaultLaunch
        WindowPresenter.isHeadlessSession = !isDefaultLaunch
        appLogger.notice(
            "启动完成 用户主动启动=\(isDefaultLaunch, privacy: .public)"
        )
        guard !isDefaultLaunch else { return }

        // URL 事件先于本方法到达（实测如此）。SwiftUI 的窗口未必在此刻就已
        // 创建，所以下一个 runloop 再收一次。显式展示只来自用户主动 reopen。
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
    ///
    /// 注意不能因为「本进程是无声启动的」就一律拒绝 reopen：用户完全可能在
    /// 宿主已被深链唤起后再去双击 App，那时必须给出窗口。
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        appLogger.notice(
            "收到 reopen 有可见窗口=\(flag, privacy: .public) 无声会话=\(WindowPresenter.isHeadlessSession, privacy: .public)"
        )
        // 一律返回 false：窗口的显示与否完全由这里决定。
        // 返回 true 会让 AppKit 执行默认行为，即再开一个窗口——
        // 深链送达已开着窗口的宿主时就会多出一个一模一样的窗口。
        // 已有可见窗口时什么都不做：激活由系统负责，无需我们插手。
        guard !flag else { return false }
        WindowPresenter.bringToFront()
        return false
    }
}

/// 附属应用不参与常规激活，展示界面前必须显式抢一次前台，
/// 否则窗口会出现在其他应用后面，用户看不到。
@MainActor
enum WindowPresenter {
    /// 请出窗口的次数。用计数而非布尔，是为了判断「某段处理期间是否有人
    /// 要求显示窗口」——布尔latch 一旦置真就永远禁用收起逻辑。
    private static var presentationCount = 0

    /// 启动期收起窗口时用：本进程是否曾显式请出过窗口。
    static var isPresentationRequested: Bool { presentationCount > 0 }

    /// 本进程是为处理深链而启动的（而非用户主动打开）。
    static var isHeadlessSession = false

    static func bringToFront() {
        presentationCount += 1
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows
            .first { $0.contentViewController != nil }?
            .makeKeyAndOrderFront(nil)
        appLogger.notice("已请出窗口")
    }

    /// 处理深链不应该让任何原本不可见的窗口变得可见。
    ///
    /// 实测：SwiftUI 为了投递 `onOpenURL` 会**新建**一个窗口，即使已经有窗口
    /// 开着也照建不误——用户每用一次右键功能就看到 App 弹出来。所以判据不是
    /// 「进程怎么启动的」，也不是「之前有没有窗口」，而是逐个窗口比对：
    /// 原本就可见的保持不动，处理期间新出现的一律收掉。
    ///
    /// 期间若用户主动 reopen，以那个显示请求为准。
    static func withPreservedVisibility(_ body: () -> Void) {
        let before = Set(
            NSApp.windows.filter { $0.isVisible }.map(\.windowNumber)
        )
        let countBefore = presentationCount
        body()

        suppressWindows(appearedSince: before, presentationCount: countBefore)
        // 窗口可能在本轮之后才被创建（实测确实如此）。
        Task { @MainActor in
            suppressWindows(
                appearedSince: before,
                presentationCount: countBefore
            )
        }
    }

    private static func suppressWindows(
        appearedSince previous: Set<Int>,
        presentationCount count: Int
    ) {
        guard presentationCount == count else { return }
        let appeared = NSApp.windows.filter {
            $0.isVisible && !previous.contains($0.windowNumber)
        }
        guard !appeared.isEmpty else { return }

        for window in appeared {
            // 留一个收起备用，供用户之后主动打开 App 时请回前台；
            // 其余直接关闭，否则每条深链都堆积一个隐藏窗口，
            // 而每个新窗口都会带来一次环境诊断（两个登录 shell）。
            if hasHiddenWindow {
                window.close()
            } else {
                window.orderOut(nil)
            }
        }
        appLogger.notice(
            "收起深链新开的窗口 数量=\(appeared.count, privacy: .public)"
        )
    }

    private static var hasHiddenWindow: Bool {
        NSApp.windows.contains { !$0.isVisible && $0.contentViewController != nil }
    }
}

@main
struct RightClickApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel(
        performInitialRefresh: !AppEnvironment.isRunningTests
    )
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
                    guard !AppEnvironment.isRunningTests,
                          delegate.isUserLaunch else {
                        return
                    }
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
