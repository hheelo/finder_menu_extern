import AppKit
import RightClickAppLogic
import RightClickCore
import SwiftUI

enum AppWindow {
    static let mainID = "main"
}
/// URL 事件由 AppDelegate 直接接收，不能挂在 SwiftUI 窗口上。
/// `WindowGroup.onOpenURL` 会为了投递事件先创建并显示一个窗口，随后再收起也会
/// 肉眼可见地闪一下。共享模型按首次访问初始化，URL 先到也可以直接处理。
@MainActor
let sharedAppModel = AppModel(
    performInitialRefresh: false
)

/// 对象本身创建很轻；内部 Sparkle 控制器直到真正检查更新时才初始化。
@MainActor
let sharedUpdaterController = UpdaterController()

/// 宿主是 `LSUIElement` 附属应用：Dock 里不出现图标。
///
/// 但它仍会被扩展的深链频繁唤起（每次「用 X 打开」「运行 CLI」都要经过它），
/// 那种唤起不该弹出任何窗口。`applicationDidFinishLaunching` 的
/// `launchIsDefaultUserInfoKey` 能区分「用户双击启动」和「为处理 URL 而启动」。
///
/// Finder 深链由 AppDelegate 直接交给模型，不进入 SwiftUI 窗口场景。用户之后
/// 双击 App 时可以把已有窗口请回来；若已关闭最后一个窗口，则由系统新建窗口。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 是否由用户自己启动（而非为处理深链）。决定要不要检查更新。
    var isUserLaunch: Bool { launchState.isUserLaunch }
    private var launchState = AppLaunchState()
    private lazy var menuBarController = MenuBarController(
        model: sharedAppModel,
        updater: sharedUpdaterController
    )

    func application(_ application: NSApplication, open urls: [URL]) {
        if launchState.receiveDeepLink() {
            // WindowGroup 可能仍会为 App 的冷启动建立默认窗口。先隐藏整个应用，
            // 比窗口出现后再 orderOut 更早，不会留下肉眼可见的一帧。
            application.hide(nil)
        }
        appLogger.notice(
            "AppDelegate 收到深链 数量=\(urls.count, privacy: .public)"
        )
        for url in urls {
            sharedAppModel.handle(url: url)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        sharedAppModel.beginLocalActionLogSession()
        sharedAppModel.onMenuBarIconEnabledChange = {
            [weak self] isEnabled in
            self?.menuBarController.setEnabled(isEnabled)
        }
        menuBarController.setEnabled(sharedAppModel.menuBarIconEnabled)

        // XCTest 通过测试运行器启动 LSUIElement App 时会把这次启动标为非默认。
        // 显式 UI 测试模式需要可见主窗口；真实深链启动仍完全依赖系统分类。
        let isDefaultLaunch = AppEnvironment.isRunningUITests ||
            (notification.userInfo?[
                NSApplication.launchIsDefaultUserInfoKey
            ] as? Bool ?? true)
        launchState.finish(isDefaultLaunch: isDefaultLaunch)
        appLogger.notice(
            "启动完成 用户主动启动=\(self.isUserLaunch, privacy: .public)"
        )
        guard !isUserLaunch else { return }

        // URL 事件先于本方法到达（实测如此）。SwiftUI 的窗口未必在此刻就已
        // 创建，所以下一个 runloop 再收一次。显式展示只来自用户主动 reopen。
        hideWindows()
        DispatchQueue.main.async { self.hideWindows() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        sharedAppModel.flushPendingMenuConfiguration()
        sharedAppModel.endLocalActionLogSession()
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
        let hasMainWindow = WindowPresenter.hasMainWindow
        appLogger.notice(
            "收到 reopen 有可见窗口=\(flag, privacy: .public) 有主窗口=\(hasMainWindow, privacy: .public) 用户启动=\(self.isUserLaunch, privacy: .public)"
        )
        switch ReopenPolicy.action(
            hasMainWindow: hasMainWindow,
            hasVisibleWindows: flag
        ) {
        case .restoreMainWindow:
            refreshForUserPresentation()
            WindowPresenter.bringMainWindowToFront()
            return false
        case .createMainWindow:
            // 设置窗口不等于主窗口。若主窗口已关闭，必须显式走 openWindow；
            // 只返回 true 会让 AppKit 因仍有设置窗口而跳过主窗口创建。
            appLogger.notice("没有主窗口，显式新建主窗口")
            refreshForUserPresentation()
            return !WindowPresenter.showOrCreateMainWindow()
        }
    }

    private func refreshForUserPresentation() {
        guard !AppEnvironment.isRunningTests else { return }
        Task { await sharedAppModel.refreshForUserPresentation() }
        sharedUpdaterController.checkInBackground()
    }
}

@main
struct RightClickApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = sharedAppModel
    @State private var updater = sharedUpdaterController
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup(id: AppWindow.mainID) {
            ContentView(updater: updater)
                .environmentObject(model)
                .frame(
                    minWidth: 720,
                    idealWidth: 840,
                    minHeight: 520,
                    idealHeight: 560
                )
                .background(MainWindowBackground())
                .task {
                    // 只在用户自己打开 App 时刷新与查更新；深链唤起时不做，
                    // 避免右键路径启动登录 shell 或冒出更新界面。
                    let isUserVisible = AppPresentation.isUserVisible(
                        isUserLaunch: delegate.isUserLaunch,
                        isPresentationRequested:
                            WindowPresenter.isPresentationRequested
                    )
                    guard !AppEnvironment.isRunningTests, isUserVisible else {
                        return
                    }
                    await model.refreshForUserPresentation()
                    updater.checkInBackground()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    let isUserVisible = AppPresentation.isUserVisible(
                        isUserLaunch: delegate.isUserLaunch,
                        isPresentationRequested:
                            WindowPresenter.isPresentationRequested
                    )
                    if newPhase == .active,
                       isUserVisible,
                       !AppEnvironment.isRunningTests {
                        Task { await model.refreshForUserPresentation() }
                        updater.checkInBackground()
                    }
                }
        }
        .windowResizability(.contentMinSize)
        // URL 由 AppDelegate 处理；明确禁止外部事件选择这个 WindowGroup，
        // 否则 SwiftUI 会先创建窗口再投递事件，造成右键操作时界面闪现。
        .handlesExternalEvents(matching: Set<String>())

        Settings {
            SettingsView()
                .environmentObject(model)
        }
        .windowResizability(.contentMinSize)

    }
}
