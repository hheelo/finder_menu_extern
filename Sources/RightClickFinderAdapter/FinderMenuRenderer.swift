@preconcurrency import AppKit
import RightClickCore

/// AppKit 菜单渲染边界。菜单结构与业务启用规则来自 Core，这里只负责稳定 tag、
/// selector、图标以及认证可用性，因而可以脱离真实 Finder 进程进行测试。
public enum FinderMenuRenderer {
    public static func menu(
        nodes: [RightClickMenuNode],
        placement: MenuPlacement,
        hasClipboardText: Bool,
        authenticationAvailable: Bool,
        target: AnyObject,
        action: Selector,
        title: String = "RightClick"
    ) -> NSMenu? {
        guard !nodes.isEmpty else { return nil }
        let menu = makeMenu(title: title)
        for node in nodes {
            menu.addItem(item(
                for: node,
                placement: placement,
                hasClipboardText: hasClipboardText,
                authenticationAvailable: authenticationAvailable,
                target: target,
                action: action
            ))
        }
        return menu
    }

    private static func makeMenu(title: String) -> NSMenu {
        let menu = NSMenu(title: title)
        // AppKit 默认会按 target/action 覆盖手工 isEnabled。
        menu.autoenablesItems = false
        return menu
    }

    private static func item(
        for node: RightClickMenuNode,
        placement: MenuPlacement,
        hasClipboardText: Bool,
        authenticationAvailable: Bool,
        target: AnyObject,
        action: Selector
    ) -> NSMenuItem {
        switch node {
        case .separator:
            return .separator()
        case let .action(menuAction, isEnabled):
            let item = NSMenuItem(
                title: menuAction.title,
                action: action,
                keyEquivalent: ""
            )
            item.target = target
            item.tag = RightClickMenuItemPayload(
                action: menuAction,
                placement: placement
            ).menuTag
            item.image = menuImage(
                named: menuAction.systemImageName,
                accessibilityDescription: menuAction.title
            )
            item.isEnabled = isEnabled && FinderActionPolicy.isSatisfied(
                menuAction,
                hasClipboardText: hasClipboardText
            ) && (
                !FinderActionPolicy.requiresAuthenticatedHost(menuAction)
                    || authenticationAvailable
            )
            return item
        case let .configuredCLI(profile, isEnabled):
            let item = NSMenuItem(
                title: L10n.format(
                    "extension.run_profile",
                    fallback: "在终端运行 %@",
                    profile.title
                ),
                action: action,
                keyEquivalent: ""
            )
            item.target = target
            item.tag = ConfiguredCLIMenuItemPayload(
                menuSlot: profile.menuSlot,
                placement: placement
            ).menuTag
            item.image = menuImage(
                named: "terminal.fill",
                accessibilityDescription: profile.title
            )
            item.isEnabled = isEnabled && authenticationAvailable
            return item
        case let .customTemplate(template, isEnabled):
            let item = NSMenuItem(
                title: template.title,
                action: action,
                keyEquivalent: ""
            )
            item.target = target
            item.tag = CustomTemplateMenuItemPayload(
                menuSlot: template.menuSlot,
                placement: placement
            ).menuTag
            item.image = menuImage(
                named: "doc.badge.plus",
                accessibilityDescription: template.title
            )
            // 自定义模板也由未沙箱化宿主落盘，与内置创建动作共享认证边界。
            item.isEnabled = isEnabled && authenticationAvailable
            return item
        case let .submenu(title, isEnabled, children):
            let root = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = makeMenu(title: title)
            for child in children {
                submenu.addItem(item(
                    for: child,
                    placement: placement,
                    hasClipboardText: hasClipboardText,
                    authenticationAvailable: authenticationAvailable,
                    target: target,
                    action: action
                ))
            }
            root.submenu = submenu
            root.isEnabled = isEnabled
            return root
        }
    }

    private static func menuImage(
        named systemName: String,
        accessibilityDescription: String
    ) -> NSImage? {
        let image = NSImage(
            systemSymbolName: systemName,
            accessibilityDescription: accessibilityDescription
        )
        image?.isTemplate = true
        return image
    }
}
