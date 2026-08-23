import AppKit
import RightClickAppLogic
import RightClickCore

@MainActor
extension AppModel {
    func refreshForUserPresentation() async {
        if !hasCompletedOnboarding && !AppEnvironment.isRunningUITests {
            shouldPresentOnboarding = true
        }
        guard !AppEnvironment.isRunningTests else { return }
        async let extensionRefresh: Void = refreshExtensionStatus()
        async let templateRefresh: Void = refreshCustomTemplates()
        async let diagnosticRefresh: Void = refreshDiagnostics()
        _ = await (extensionRefresh, templateRefresh, diagnosticRefresh)
    }

    func addMonitoredDirectories() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = true
        panel.prompt = L10n.text(
            "button.add_monitored_directory",
            fallback: "添加目录"
        )
        guard panel.runModal() == .OK else { return }

        let selectedPaths = panel.urls.map { $0.standardizedFileURL.path }
        menuConfigurationStore.updateImmediately { updated in
            updated.monitoredDirectories = MonitoredDirectoryPolicy
                .sanitizedPaths(updated.monitoredDirectories + selectedPaths)
        }
    }

    func removeMonitoredDirectory(_ path: String) {
        menuConfigurationStore.updateImmediately {
            $0.monitoredDirectories.removeAll { $0 == path }
        }
    }

    func monitorAllDirectories() {
        menuConfigurationStore.updateImmediately {
            $0.monitoredDirectories = []
        }
    }

    func completeOnboarding() {
        guard !hasCompletedOnboarding else { return }
        settings.hasCompletedOnboarding = true
        hasCompletedOnboarding = true
        shouldPresentOnboarding = false
    }

    func skipOnboarding() {
        completeOnboarding()
    }

    func restartOnboarding() {
        settings.hasCompletedOnboarding = false
        hasCompletedOnboarding = false
        shouldPresentOnboarding = true
    }

    func persistMenuConfigurationImmediately() {
        menuConfigurationStore.persistImmediately()
    }

    func flushPendingMenuConfiguration() {
        menuConfigurationStore.flushPendingPersist()
    }

    func restartFinder() {
        restartFinder(successStatus: L10n.text(
            "status.restarted_finder",
            fallback: "Finder 已重新启动"
        ))
    }

}
