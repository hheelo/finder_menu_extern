@preconcurrency import AppKit
@preconcurrency import FinderSync
import RightClickCore

final class FinderSync: FIFinderSync {
    private let controller = FIFinderSyncController.default()
    private let fileCreator = FileCreator()
    private let requestStore = RequestStore()

    override init() {
        super.init()
        controller.directoryURLs = SharedSettings.shared.monitoredURLs
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
            default:
                try routeToHost(action, context: context)
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

    private func routeToHost(
        _ action: RightClickAction,
        context: SelectionContext
    ) throws {
        let request = ActionRequest(
            action: action,
            selectedURLs: context.effectiveURLs,
            targetedURL: context.targetedURL
        )
        try requestStore.enqueue(request)
        guard let deepLink = request.deepLink else { return }
        NSWorkspace.shared.open(deepLink)
    }
}

private final class ActionBox: NSObject {
    let action: RightClickAction

    init(_ action: RightClickAction) {
        self.action = action
    }
}
