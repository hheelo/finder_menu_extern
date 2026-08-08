import Sparkle
import os

/// 应用内更新。
///
/// 为什么需要它：Ad-hoc 签名的 App 从浏览器下载会被打上 `com.apple.quarantine`，
/// Gatekeeper 因此拦一次。而 Sparkle 用 URLSession 下载更新包，不会打这个标记
/// （已实测：curl 下载的同一个 DMG 只有 `com.apple.provenance`），
/// Gatekeeper 不评估未隔离的文件，所以更新过程完全没有提示。
/// 净效果：只有首次安装需要放行一次，后续更新静默完成。
///
/// 更新包用 EdDSA 私钥签名（`SUPublicEDKey` 是对应公钥），与 Apple 的证书体系
/// 无关，因此 Ad-hoc 签名也能安全校验。代价是没有 Developer ID 就无法轮换密钥。
@MainActor
final class UpdaterController {
    private var controller: SPUStandardUpdaterController?
    private var hasCheckedInBackground = false

    /// 深链无声唤起只需执行 Finder 动作，不初始化 Sparkle/XPC。用户显示窗口、
    /// 手动或后台检查更新时才按需创建。
    private func makeControllerIfNeeded() -> SPUStandardUpdaterController {
        if let controller { return controller }
        let created = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller = created
        return created
    }

    /// 用户点「检查更新」：无论有没有新版都给出反馈。
    func checkForUpdates() {
        appLogger.notice("用户手动检查更新")
        makeControllerIfNeeded().checkForUpdates(nil)
    }

    /// 用户自己打开 App 时查一次：只有发现新版本才出现界面。
    ///
    /// 不用定时检查，也不在深链唤起时检查——宿主经常被无声唤起，
    /// 那种时候弹出更新界面会让人莫名其妙。
    func checkInBackground() {
        // 每进程只查一次：窗口被关闭后重新创建时，视图的 .task 会再次执行。
        guard !hasCheckedInBackground else { return }
        hasCheckedInBackground = true
        appLogger.notice("后台检查更新")
        makeControllerIfNeeded().updater.checkForUpdatesInBackground()
    }
}
