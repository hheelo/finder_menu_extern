import AppKit
import RightClickAppLogic
import RightClickCore
import UniformTypeIdentifiers

@MainActor
extension AppModel {
    func beginLocalActionLogSession() {
        actionLogSessionTracker.begin()
    }

    func endLocalActionLogSession() {
        actionLogSessionTracker.end()
    }

    func exportLocalActionLog() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "RightClick-Local-Action-Log.txt"
        panel.title = L10n.text(
            "settings.export_local_log",
            fallback: "导出本地动作日志"
        )
        guard panel.runModal() == .OK, let destination = panel.url else {
            return
        }

        let extensionRecords = extensionActionLogURL.map {
            LocalActionLogStore.load(from: $0)
        } ?? []
        let report = LocalActionLogReport.make(
            hostRecords: actionLogStore.records(),
            extensionRecords: extensionRecords,
            appVersion: AppVersion.displayString ?? "unknown"
        )
        do {
            try Data(report.utf8).write(to: destination, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: destination.path
            )
            lastStatus = L10n.text(
                "status.exported_local_log",
                fallback: "本地动作日志已导出"
            )
        } catch {
            recordFailure(L10n.format(
                "error.export_local_log",
                fallback: "无法导出本地动作日志：%@",
                error.localizedDescription
            ))
        }
    }

    func exportSettings() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "RightClick-Settings.rightclick-settings.json"
        panel.title = L10n.text(
            "settings.export_settings",
            fallback: "导出 RightClick 设置"
        )
        guard panel.runModal() == .OK, let destination = panel.url else {
            return
        }
        do {
            let data = try menuConfigurationStore.exportSettingsData()
            try data.write(to: destination, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: destination.path
            )
            lastStatus = L10n.text(
                "status.exported_settings",
                fallback: "RightClick 设置已导出"
            )
        } catch {
            recordFailure(L10n.format(
                "error.export_settings",
                fallback: "无法导出 RightClick 设置：%@",
                error.localizedDescription
            ))
        }
    }

    func importSettings() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.prompt = L10n.text("button.import_settings", fallback: "导入设置")
        guard panel.runModal() == .OK, let source = panel.url else { return }
        do {
            let values = try source.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? 0) <= MenuConfigurationTransfer.maximumDocumentSize
            else {
                throw MenuConfigurationTransferError.documentTooLarge
            }
            let data = try Data(contentsOf: source)
            try menuConfigurationStore.importSettingsData(data)
            lastStatus = L10n.text(
                "status.imported_settings",
                fallback: "RightClick 设置已导入"
            )
            Task { await refreshDiagnostics(force: true) }
        } catch {
            recordFailure(L10n.format(
                "error.import_settings",
                fallback: "无法导入 RightClick 设置：%@",
                error.localizedDescription
            ))
        }
    }

    func resetConfigurationAfterRecovery() {
        do {
            try menuConfigurationStore.resetAfterRecovery()
            lastStatus = L10n.text(
                "status.reset_settings",
                fallback: "Finder 菜单设置已重置"
            )
            Task { await refreshDiagnostics(force: true) }
        } catch {
            recordFailure(L10n.format(
                "error.reset_settings",
                fallback: "无法重置 Finder 菜单设置：%@",
                error.localizedDescription
            ))
        }
    }

    func clearErrors() {
        errorHistory.removeAll()
    }

}
