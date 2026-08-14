import AppKit
import RightClickCore

/// 可选菜单栏入口由 AppKit 独立持有，不进入 SwiftUI 根 Scene 图。
///
/// v0.9.1 曾用 `MenuBarExtra(isInserted:)` 直接绑定 `@Published` 设置；在
/// macOS 26.6 上，即使开关保持关闭，Scene 仍会持续把值写回模型，引发
/// AttributeGraph 更新反馈环和无上限内存增长。`NSStatusItem` 的生命周期只有
/// `setEnabled(_:)` 这一条单向入口，不会反向修改设置。
@MainActor
final class MenuBarController: NSObject {
    private let model: AppModel
    private let updater: UpdaterController
    private var statusItem: NSStatusItem?

    init(model: AppModel, updater: UpdaterController) {
        self.model = model
        self.updater = updater
    }

    func setEnabled(_ isEnabled: Bool) {
        if isEnabled {
            installIfNeeded()
        } else {
            removeIfNeeded()
        }
    }

    private func installIfNeeded() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength
        )
        if let button = item.button {
            let image = NSImage(
                systemSymbolName: "cursorarrow.click.2",
                accessibilityDescription: "RightClick"
            )
            image?.isTemplate = true
            button.image = image
            button.toolTip = "RightClick"
        }
        item.menu = makeMenu()
        statusItem = item
        appLogger.notice("已启用菜单栏入口")
    }

    private func removeIfNeeded() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
        appLogger.notice("已关闭菜单栏入口")
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        addItem(
            to: menu,
            title: L10n.text(
                "menu.show_rightclick",
                fallback: "显示 RightClick"
            ),
            action: #selector(showRightClick)
        )
        addItem(
            to: menu,
            title: L10n.text("button.settings", fallback: "设置…"),
            action: #selector(showSettings)
        )
        menu.addItem(.separator())
        addItem(
            to: menu,
            title: L10n.text(
                "button.copy_diagnostics",
                fallback: "复制诊断信息"
            ),
            action: #selector(copyDiagnostics)
        )
        addItem(
            to: menu,
            title: L10n.text(
                "button.restart_finder",
                fallback: "重启 Finder"
            ),
            action: #selector(restartFinder)
        )
        menu.addItem(.separator())
        addItem(
            to: menu,
            title: L10n.text(
                "button.quit",
                fallback: "退出 RightClick"
            ),
            action: #selector(quit)
        )
        return menu
    }

    private func addItem(
        to menu: NSMenu,
        title: String,
        action: Selector
    ) {
        let item = NSMenuItem(
            title: title,
            action: action,
            keyEquivalent: ""
        )
        item.target = self
        menu.addItem(item)
    }

    @objc private func showRightClick() {
        WindowPresenter.showOrCreateMainWindow()
        refreshForUserPresentation()
    }

    @objc private func showSettings() {
        WindowPresenter.showSettings()
    }

    @objc private func copyDiagnostics() {
        model.copyDiagnostics()
    }

    @objc private func restartFinder() {
        model.restartFinder()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func refreshForUserPresentation() {
        Task { await model.refreshForUserPresentation() }
        updater.checkInBackground()
    }
}
