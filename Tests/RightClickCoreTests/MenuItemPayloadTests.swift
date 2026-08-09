import Foundation
import Testing
@testable import RightClickCore

struct MenuItemPayloadTests {
    /// 固定动作的 tag 从 1 开始，自定义模板的区段基址是 100。动作加到 100 个
    /// 就会与模板槽位撞车，而那种冲突在运行时只表现为「点了执行成另一个动作」。
    @Test
    func fixedActionsStayBelowTheDynamicSectionBase() {
        #expect(RightClickAction.allMenuActions.count < 100)
    }

    @Test
    func decodesEveryFixedActionBackToItself() {
        for placement in MenuPlacement.allCases {
            for action in RightClickAction.allMenuActions {
                let tag = RightClickMenuItemPayload(
                    action: action,
                    placement: placement
                ).menuTag
                guard case let .action(decoded) = MenuItemPayload(
                    menuTag: tag
                ) else {
                    Issue.record("tag \(tag) 未解码成固定动作")
                    continue
                }
                #expect(decoded.action == action)
                #expect(decoded.placement == placement)
            }
        }
    }

    @Test
    func decodesDynamicSlotsToTheirOwnCases() {
        for slot in [
            CLIProfile.validMenuSlots.lowerBound,
            CLIProfile.validMenuSlots.upperBound
        ] {
            let tag = ConfiguredCLIMenuItemPayload(
                menuSlot: slot,
                placement: .items
            ).menuTag
            guard case let .configuredCLI(decoded) = MenuItemPayload(
                menuTag: tag
            ) else {
                Issue.record("CLI slot \(slot) 未解码成动态 CLI")
                continue
            }
            #expect(decoded.menuSlot == slot)
        }

        for slot in [
            CustomFileTemplate.validMenuSlots.lowerBound,
            CustomFileTemplate.validMenuSlots.upperBound
        ] {
            let tag = CustomTemplateMenuItemPayload(
                menuSlot: slot,
                placement: .container
            ).menuTag
            guard case let .customTemplate(decoded) = MenuItemPayload(
                menuTag: tag
            ) else {
                Issue.record("模板 slot \(slot) 未解码成自定义模板")
                continue
            }
            #expect(decoded.menuSlot == slot)
        }
    }

    @Test
    func rejectsTagsOutsideEverySection() {
        // 0 留给「不携带动作」，负数与越界的 placement 都不该被接受。
        #expect(MenuItemPayload(menuTag: 0) == nil)
        #expect(MenuItemPayload(menuTag: -1) == nil)
        #expect(MenuItemPayload(menuTag: 9_999) == nil)
    }
}
