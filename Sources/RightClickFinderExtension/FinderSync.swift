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
            menu.addItem(actionItem(.copyPath))
            menu.addItem(actionItem(.copyFilename))
            menu.addItem(.separator())
            menu.addItem(actionItem(.openInVSCode))
            menu.addItem(actionItem(.openInCodex))
            menu.addItem(runSubmenu())
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

    private func actionItem(_ action: RightClickAction) -> NSMenuItem {
        let item = NSMenuItem(
            title: action.title,
            action: #selector(performAction(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = ActionBox(action)
        return item
    }

    private func runSubmenu() -> NSMenuItem {
        let root = NSMenuItem(title: "在终端中运行", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: root.title)
        submenu.addItem(actionItem(.runCodexCLI))
        submenu.addItem(actionItem(.runClaudeCode))
        root.submenu = submenu
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
                _ = try fileCreator.create(template, in: directory)
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
                openHost(for: .codex, context: context)
            case .runClaudeCode:
                openHost(for: .claude, context: context)
            }
        } catch {
            NSLog("RightClick action failed: %@", error.localizedDescription)
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
            .map { URL(fileURLWithPath: "/Applications/\($0).app") }
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
        )
    }

    private func openHost(
        for command: CLICommand,
        context: SelectionContext
    ) {
        guard let directory = context.workingDirectory,
              let deepLink = CLIInvocation(
                  command: command,
                  workingDirectory: directory
              ).deepLink else {
            return
        }
        NSWorkspace.shared.open(deepLink)
    }
}

private enum FinderActionError: LocalizedError {
    case applicationNotFound(String)

    var errorDescription: String? {
        switch self {
        case let .applicationNotFound(name):
            "未找到 \(name)，请先安装应用。"
        }
    }
}

private final class ActionBox: NSObject {
    let action: RightClickAction

    init(_ action: RightClickAction) {
        self.action = action
    }
}
