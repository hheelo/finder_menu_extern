import Foundation
import Testing
@testable import RightClickCore

struct MenuItemPayloadTests {
    /// 固定动作的 tag 从 1 开始，自定义模板的区段基址是 100。动作加到 100 个
    /// 就会与模板槽位撞车，而那种冲突在运行时只表现为「点了执行成另一个动作」。
    @Test
    func fixedActionsStayBelowTheDynamicSectionBase() {
        #expect(
            RightClickAction.allMenuActions.count
                < MenuTagSpace.customTemplateBase
        )
    }

    @Test
    func menuTagSegmentsAreDisjointAndStayInsideTheStride() {
        let segments = MenuTagSpace.actionCodeSegments

        #expect(MenuTagSpace.arePairwiseDisjoint(segments))
        #expect(segments.allSatisfy {
            $0.lowerBound > 0
                && $0.upperBound <= MenuTagSpace.actionStride
        })
    }

    @Test
    func overlapDetectorRejectsASyntheticSlotCollision() {
        let collisionStart = MenuTagSpace.customTemplateCodes.upperBound - 1
        let collisionEnd = MenuTagSpace.configuredCLICodes.upperBound
        let collision = [
            MenuTagSpace.customTemplateCodes,
            collisionStart..<collisionEnd
        ]

        #expect(!MenuTagSpace.arePairwiseDisjoint(collision))
    }

    /// `menuTag` 是已发出的跨进程契约：Finder 里可能还挂着旧版本构建的菜单项。
    /// 这里钉死若干已发布的编号，任何对 `allMenuActions` 的重排或插入都会报红。
    /// 只允许在末尾追加——那不会改动下面任何一个数字。
    @Test
    func publishedMenuTagsNeverShift() {
        let published: [(RightClickAction, Int)] = [
            (.copyPath, 1),
            (.copyFilename, 2),
            (.openInVSCode, 3),
            (.openInCodex, 4),
            (.openInTerminal, 5),
            (.runCodexCLI, 6),
            (.runClaudeCode, 7),
            (.createFile(.text), 8),
            (.copyFileURL, 15),
            (.copyShellPath, 16),
            (.copyParentPath, 17),
            (.openInCursor, 18),
            (.openInDefaultApplication, 23),
            (.createFolder, 24),
            (.createFileFromClipboard, 25),
            (.copyRelativePath, 26)
        ]
        for (action, tag) in published {
            #expect(
                action.menuTag == tag,
                "\(action.logDescription) 的 tag 从 \(tag) 变成了 \(action.menuTag)"
            )
        }
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
