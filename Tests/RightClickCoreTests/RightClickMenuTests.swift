import Foundation
import Testing
@testable import RightClickCore

struct RightClickMenuTests {
    private let folder = URL(fileURLWithPath: "/tmp/example", isDirectory: true)

    @Test
    func toolbarMenuOffersNothing() {
        let context = SelectionContext(selectedURLs: [], targetedURL: folder)
        #expect(
            RightClickMenu.nodes(placement: .toolbar, context: context)
                .isEmpty
        )
        #expect(MenuPlacement.toolbar.providesContextActions == false)
    }

    @Test
    func backgroundAndSidebarMenusIgnoreSelection() {
        #expect(MenuPlacement.container.usesTargetedURLOnly)
        #expect(MenuPlacement.sidebar.usesTargetedURLOnly)
        #expect(MenuPlacement.items.usesTargetedURLOnly == false)
    }

    @Test
    func disablesEverySelectionActionWithoutSelection() {
        let context = SelectionContext(selectedURLs: [], targetedURL: nil)
        let nodes = RightClickMenu.nodes(placement: .items, context: context)

        #expect(!nodes.isEmpty)
        for node in nodes {
            switch node {
            case let .action(_, isEnabled):
                #expect(isEnabled == false)
            case let .submenu(title, isEnabled, _):
                #expect(isEnabled == false, "\(title) 应当置灰")
            case .separator:
                break
            }
        }
    }

    @Test
    func enablesActionsForATargetedFolder() {
        let context = SelectionContext(selectedURLs: [], targetedURL: folder)
        let nodes = RightClickMenu.nodes(placement: .container, context: context)

        #expect(nodes.contains(.action(.copyPath, isEnabled: true)))
        #expect(nodes.contains(.action(.openInVSCode, isEnabled: true)))
        #expect(enabledSubmenu(named: "新建文件", in: nodes))
        #expect(enabledSubmenu(named: "在终端中打开", in: nodes))
        #expect(enabledSubmenu(named: "运行 AI CLI", in: nodes))
    }

    @Test
    func offersEveryTemplateAndTerminalProfile() {
        let context = SelectionContext(selectedURLs: [], targetedURL: folder)
        let nodes = RightClickMenu.nodes(placement: .items, context: context)

        #expect(
            submenuItems(named: "新建文件", in: nodes)?.count
                == FileTemplate.allCases.count
        )
        #expect(
            submenuItems(named: "在终端中打开", in: nodes)?.count
                == TerminalProfile.allCases.count
        )
    }

    /// 复制类动作在文件上可用，但新建文件要落到父目录。
    @Test
    func keepsNewFileAvailableForASelectedFile() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let context = SelectionContext(selectedURLs: [file], targetedURL: nil)
        let nodes = RightClickMenu.nodes(placement: .items, context: context)

        #expect(nodes.contains(.action(.copyFilename, isEnabled: true)))
        #expect(enabledSubmenu(named: "新建文件", in: nodes))
        #expect(
            context.creationDirectory?.path
                == file.deletingLastPathComponent().path
        )
    }

    /// 菜单项跨进程往返只能携带 tag，动作必须能无损编解码，
    /// 否则回调里认不出动作，点击会被静默丢弃。
    @Test
    func everyActionRoundTripsThroughItsMenuTag() {
        for action in RightClickAction.allMenuActions {
            let tag = action.menuTag
            #expect(tag > 0, "\(action.title) 的 tag 不能是 0")
            #expect(RightClickAction(menuTag: tag) == action)
        }
    }

    @Test
    func rejectsTagsOutsideTheKnownRange() {
        #expect(RightClickAction(menuTag: 0) == nil)
        #expect(RightClickAction(menuTag: -1) == nil)
        #expect(
            RightClickAction(
                menuTag: RightClickAction.allMenuActions.count + 1
            ) == nil
        )
    }

    /// 菜单里出现的每个动作都必须在 allMenuActions 里有编号。
    @Test
    func menuOnlyOffersEncodableActions() {
        let context = SelectionContext(selectedURLs: [], targetedURL: folder)
        var checked = 0

        func verify(_ nodes: [RightClickMenuNode]) {
            for node in nodes {
                switch node {
                case let .action(action, _):
                    #expect(action.menuTag > 0, "\(action.title) 缺少编号")
                    checked += 1
                case let .submenu(_, _, items):
                    verify(items)
                case .separator:
                    break
                }
            }
        }

        for placement in MenuPlacement.allCases {
            verify(RightClickMenu.nodes(placement: placement, context: context))
        }
        #expect(checked > 0)
    }

    private func submenuItems(
        named title: String,
        in nodes: [RightClickMenuNode]
    ) -> [RightClickMenuNode]? {
        nodes.lazy.compactMap { node -> [RightClickMenuNode]? in
            guard case let .submenu(name, _, items) = node,
                  name == title else {
                return nil
            }
            return items
        }.first
    }

    private func enabledSubmenu(
        named title: String,
        in nodes: [RightClickMenuNode]
    ) -> Bool {
        nodes.contains { node in
            guard case let .submenu(name, isEnabled, _) = node else {
                return false
            }
            return name == title && isEnabled
        }
    }
}
