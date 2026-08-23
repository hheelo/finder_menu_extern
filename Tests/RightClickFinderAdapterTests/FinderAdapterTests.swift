@preconcurrency import AppKit
import Foundation
import RightClickCore
import Testing
@testable import RightClickFinderAdapter

@MainActor
struct FinderAdapterTests {
    @Test
    func backgroundAndSidebarDiscardStaleSelection() {
        let selected = URL(fileURLWithPath: "/tmp/stale.txt")
        let targeted = URL(fileURLWithPath: "/tmp", isDirectory: true)

        for placement in [MenuPlacement.container, .sidebar] {
            let context = FinderSelectionResolver.context(
                placement: placement,
                selectedURLs: [selected],
                targetedURL: targeted
            )
            #expect(context.selectedURLs.isEmpty)
            #expect(context.effectiveURLs == [targeted])
        }
    }

    @Test
    func itemPlacementKeepsTheCurrentSelection() {
        let selected = URL(fileURLWithPath: "/tmp/file.txt")
        let context = FinderSelectionResolver.context(
            placement: .items,
            selectedURLs: [selected],
            targetedURL: URL(fileURLWithPath: "/tmp", isDirectory: true)
        )
        #expect(context.selectedURLs == [selected])
        #expect(context.effectiveURLs == [selected])
    }

    @Test
    func rendererKeepsManualEnablementAndStablePayloads() throws {
        let target = MenuTarget()
        let nodes: [RightClickMenuNode] = [
            .action(.copyPath, isEnabled: true),
            .action(.openInVSCode, isEnabled: true)
        ]
        let menu = try #require(FinderMenuRenderer.menu(
            nodes: nodes,
            placement: .items,
            hasClipboardText: true,
            authenticationAvailable: false,
            target: target,
            action: #selector(MenuTarget.perform(_:))
        ))

        #expect(!menu.autoenablesItems)
        #expect(menu.items[0].isEnabled)
        #expect(!menu.items[1].isEnabled)
        #expect(
            MenuItemPayload(menuTag: menu.items[0].tag)
                == .action(RightClickMenuItemPayload(
                    action: .copyPath,
                    placement: .items
                ))
        )
    }

    @Test
    func clipboardCreationIsDisabledWithoutReadingClipboardContents() throws {
        let menu = try #require(FinderMenuRenderer.menu(
            nodes: [.action(.createFileFromClipboard, isEnabled: true)],
            placement: .container,
            hasClipboardText: false,
            authenticationAvailable: true,
            target: MenuTarget(),
            action: #selector(MenuTarget.perform(_:))
        ))
        #expect(!menu.items[0].isEnabled)
    }

    @Test
    func dynamicCLIRequiresAuthenticationButTemplateDoesNot() throws {
        let cli = CLIProfile(
            id: "gemini",
            title: "Gemini",
            executable: "gemini",
            menuSlot: 4
        )
        let template = CustomFileTemplate(
            id: "notes",
            title: "Notes.md",
            filename: "Notes.md",
            menuSlot: 7
        )
        let menu = try #require(FinderMenuRenderer.menu(
            nodes: [
                .configuredCLI(cli, isEnabled: true),
                .customTemplate(template, isEnabled: true)
            ],
            placement: .container,
            hasClipboardText: true,
            authenticationAvailable: false,
            target: MenuTarget(),
            action: #selector(MenuTarget.perform(_:))
        ))

        #expect(!menu.items[0].isEnabled)
        #expect(menu.items[1].isEnabled)
        #expect(
            MenuItemPayload(menuTag: menu.items[0].tag)
                == .configuredCLI(ConfiguredCLIMenuItemPayload(
                    menuSlot: 4,
                    placement: .container
                ))
        )
        #expect(
            MenuItemPayload(menuTag: menu.items[1].tag)
                == .customTemplate(CustomTemplateMenuItemPayload(
                    menuSlot: 7,
                    placement: .container
                ))
        )
    }

    @Test
    func nestedMenusAlsoDisableAutomaticValidation() throws {
        let menu = try #require(FinderMenuRenderer.menu(
            nodes: [.submenu(
                title: "Nested",
                isEnabled: true,
                items: [.action(.copyPath, isEnabled: true)]
            )],
            placement: .items,
            hasClipboardText: true,
            authenticationAvailable: true,
            target: MenuTarget(),
            action: #selector(MenuTarget.perform(_:))
        ))
        let submenu = try #require(menu.items.first?.submenu)
        #expect(!submenu.autoenablesItems)
        #expect(submenu.items.first?.isEnabled == true)
    }
}

@MainActor
private final class MenuTarget: NSObject {
    @objc func perform(_ sender: NSMenuItem) {}
}
