@preconcurrency import AppKit
@preconcurrency import FinderSync
import RightClickCore

final class FinderSync: FIFinderSync {
    private let controller = FIFinderSyncController.default()
    private let fileCreator = FileCreator()

    override init() {
        super.init()
        controller.directoryURLs = [
            URL(fileURLWithPath: "/", isDirectory: true)
        ]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let menu = NSMenu(title: "RightClick")
        let context = currentContext

        if menuKind == .contextualMenuForItems {
            let hasSelection = !context.effectiveURLs.isEmpty
            menu.addItem(actionItem(.copyPath, isEnabled: hasSelection))
            menu.addItem(actionItem(.copyFilename, isEnabled: hasSelection))
            menu.addItem(.separator())
            menu.addItem(
                actionItem(
                    .openInVSCode,
                    isEnabled: hasSelection && isApplicationInstalled(
                        bundleIdentifiers: ["com.microsoft.VSCode"],
                        applicationNames: ["Visual Studio Code"]
                    )
                )
            )
            menu.addItem(
                actionItem(
                    .openInCodex,
                    isEnabled: hasSelection && isApplicationInstalled(
                        bundleIdentifiers: ["com.openai.codex"],
                        applicationNames: ["Codex"]
                    )
                )
            )
            menu.addItem(
                runSubmenu(isEnabled: context.workingDirectory != nil)
            )
        }

        if menuKind == .contextualMenuForContainer ||
            menuKind == .contextualMenuForItems {
            menu.addItem(.separator())
            let newFile = newFileSubmenu()
            newFile.isEnabled = context.creationDirectory != nil
            menu.addItem(newFile)
        }

        return menu.items.isEmpty ? nil : menu
    }

    private var currentContext: SelectionContext {
        SelectionContext(
            selectedURLs: controller.selectedItemURLs() ?? [],
            targetedURL: controller.targetedURL()
        )
    }

    private func actionItem(
        _ action: RightClickAction,
        isEnabled: Bool = true
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: action.title,
            action: #selector(performAction(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = ActionBox(action)
        item.isEnabled = isEnabled
        return item
    }

    private func runSubmenu(isEnabled: Bool) -> NSMenuItem {
        let root = NSMenuItem(title: "在终端中运行", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: root.title)
        submenu.addItem(actionItem(.runCodexCLI, isEnabled: isEnabled))
        submenu.addItem(actionItem(.runClaudeCode, isEnabled: isEnabled))
        root.submenu = submenu
        root.isEnabled = isEnabled
        return root
    }

    private func newFileSubmenu() -> NSMenuItem {
        let root = NSMenuItem(title: "新建文件", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: root.title)
        for template in FileTemplate.allCases {
            submenu.addItem(actionItem(.createFile(template)))
        }
        root.submenu = submenu
        return root
    }

    @objc private func performAction(_ sender: NSMenuItem) {
        guard let action = (sender.representedObject as? ActionBox)?.action else {
            return
        }
        let context = currentContext

        do {
            switch action {
            case .copyPath:
                copy(ClipboardText.paths(for: context.effectiveURLs))
            case .copyFilename:
                copy(ClipboardText.filenames(for: context.effectiveURLs))
            case let .createFile(template):
                guard let directory = context.creationDirectory else { return }
                let createdURL = try fileCreator.create(template, in: directory)
                NSWorkspace.shared.activateFileViewerSelecting([createdURL])
            case .openInVSCode:
                try open(
                    context.effectiveURLs,
                    bundleIdentifiers: ["com.microsoft.VSCode"],
                    applicationNames: ["Visual Studio Code"]
                )
            case .openInCodex:
                try open(
                    context.effectiveURLs,
                    bundleIdentifiers: ["com.openai.codex"],
                    applicationNames: ["Codex"]
                )
            case .runCodexCLI:
                try openHost(for: .codex, context: context)
            case .runClaudeCode:
                try openHost(for: .claude, context: context)
            }
        } catch {
            NSLog("RightClick action failed: %@", error.localizedDescription)
            Self.present(message: error.localizedDescription)
        }
    }

    private func copy(_ value: String) {
        guard !value.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func open(
        _ urls: [URL],
        bundleIdentifiers: [String],
        applicationNames: [String]
    ) throws {
        let workspace = NSWorkspace.shared
        let installedURL = bundleIdentifiers.lazy.compactMap {
            workspace.urlForApplication(withBundleIdentifier: $0)
        }.first
        let conventionalURL = applicationNames.lazy
            .flatMap { name in
                [
                    URL(fileURLWithPath: "/Applications/\(name).app"),
                    FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent("Applications/\(name).app")
                ]
            }
            .first { FileManager.default.fileExists(atPath: $0.path) }

        guard let applicationURL = installedURL ?? conventionalURL else {
            throw FinderActionError.applicationNotFound(
                applicationNames.first ?? "应用"
            )
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.open(
            urls,
            withApplicationAt: applicationURL,
            configuration: configuration
        ) { _, error in
            guard let error else { return }
            NSLog("RightClick open failed: %@", error.localizedDescription)
            FinderSync.present(message: error.localizedDescription)
        }
    }

    private func openHost(
        for command: CLICommand,
        context: SelectionContext
    ) throws {
        guard let directory = context.workingDirectory,
              let deepLink = CLIInvocation(
                  command: command,
                  workingDirectory: directory
              ).deepLink else {
            throw FinderActionError.invalidWorkingDirectory
        }
        guard NSWorkspace.shared.open(deepLink) else {
            throw FinderActionError.hostApplicationUnavailable
        }
    }

    private func isApplicationInstalled(
        bundleIdentifiers: [String],
        applicationNames: [String]
    ) -> Bool {
        let workspace = NSWorkspace.shared
        if bundleIdentifiers.contains(where: {
            workspace.urlForApplication(withBundleIdentifier: $0) != nil
        }) {
            return true
        }

        return applicationNames.contains {
            FileManager.default.fileExists(
                atPath: "/Applications/\($0).app"
            ) || FileManager.default.fileExists(
                atPath: FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Applications/\($0).app").path
            )
        }
    }

    private static func present(message: String) {
        DispatchQueue.main.async {
            NSSound.beep()
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "RightClick 操作失败"
            alert.informativeText = message
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }
}

private enum FinderActionError: LocalizedError {
    case applicationNotFound(String)
    case invalidWorkingDirectory
    case hostApplicationUnavailable

    var errorDescription: String? {
        switch self {
        case let .applicationNotFound(name):
            "未找到 \(name)，请先安装应用。"
        case .invalidWorkingDirectory:
            "无法确定有效的工作目录。"
        case .hostApplicationUnavailable:
            "无法启动 RightClick，请确认 App 仍位于 Applications 文件夹中。"
        }
    }
}

private final class ActionBox: NSObject {
    let action: RightClickAction

    init(_ action: RightClickAction) {
        self.action = action
    }
}
