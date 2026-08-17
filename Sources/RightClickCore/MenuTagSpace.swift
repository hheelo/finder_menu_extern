import Foundation

/// Finder 跨进程菜单 tag 的唯一空间定义。
///
/// 低三位是动作码，高位是菜单位置。三类动作码必须永久互不重叠；已发布
/// 的基址与 stride 都是线上格式，不能原地修改。
public enum MenuTagSpace {
    public static let actionStride = 1_000
    public static let customTemplateBase = 100
    public static let configuredCLIBase = 500

    public static var fixedActionCodes: Range<Int> {
        1..<(RightClickAction.allMenuActions.count + 1)
    }

    public static var customTemplateCodes: Range<Int> {
        let lower = customTemplateBase
            + CustomFileTemplate.validMenuSlots.lowerBound
        let upper = customTemplateBase
            + CustomFileTemplate.validMenuSlots.upperBound + 1
        return lower..<upper
    }

    public static var configuredCLICodes: Range<Int> {
        let lower = configuredCLIBase + CLIProfile.validMenuSlots.lowerBound
        let upper = configuredCLIBase
            + CLIProfile.validMenuSlots.upperBound + 1
        return lower..<upper
    }

    public static var actionCodeSegments: [Range<Int>] {
        [fixedActionCodes, customTemplateCodes, configuredCLICodes]
    }

    public static func arePairwiseDisjoint(
        _ segments: [Range<Int>]
    ) -> Bool {
        for leftIndex in segments.indices {
            for rightIndex in segments.indices where rightIndex > leftIndex {
                if segments[leftIndex].overlaps(segments[rightIndex]) {
                    return false
                }
            }
        }
        return true
    }
}

private protocol MenuTagValue: Equatable, Sendable {
    var actionCode: Int { get }
    init?(actionCode: Int)
}

private struct EncodedMenuItemPayload<Value: MenuTagValue>:
    Equatable, Sendable {
    let value: Value
    let placement: MenuPlacement

    var menuTag: Int {
        placement.menuTagCode * MenuTagSpace.actionStride + value.actionCode
    }

    init(value: Value, placement: MenuPlacement) {
        self.value = value
        self.placement = placement
    }

    init?(menuTag: Int) {
        let placementCode = menuTag / MenuTagSpace.actionStride
        let actionCode = menuTag % MenuTagSpace.actionStride
        guard let placement = MenuPlacement(menuTagCode: placementCode),
              let value = Value(actionCode: actionCode) else {
            return nil
        }
        self.init(value: value, placement: placement)
    }
}

private struct FixedActionTagValue: MenuTagValue {
    let action: RightClickAction

    var actionCode: Int { action.menuTag }

    init(action: RightClickAction) {
        self.action = action
    }

    init?(actionCode: Int) {
        guard let action = RightClickAction(menuTag: actionCode) else {
            return nil
        }
        self.action = action
    }
}

private protocol MenuSlotTagSegment: Sendable {
    static var base: Int { get }
    static var validSlots: ClosedRange<Int> { get }
}

private enum CustomTemplateTagSegment: MenuSlotTagSegment {
    static let base = MenuTagSpace.customTemplateBase
    static let validSlots = CustomFileTemplate.validMenuSlots
}

private enum ConfiguredCLITagSegment: MenuSlotTagSegment {
    static let base = MenuTagSpace.configuredCLIBase
    static let validSlots = CLIProfile.validMenuSlots
}

private struct MenuSlotTagValue<Segment: MenuSlotTagSegment>:
    MenuTagValue {
    let slot: Int

    var actionCode: Int { Segment.base + slot }

    init(slot: Int) {
        self.slot = slot
    }

    init?(actionCode: Int) {
        let slot = actionCode - Segment.base
        guard Segment.validSlots.contains(slot) else { return nil }
        self.slot = slot
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.slot == rhs.slot
    }
}

/// Finder 把菜单项送出扩展进程、再把点击送回来时，只能可靠保留整数 tag。
public struct RightClickMenuItemPayload: Equatable, Sendable {
    public let action: RightClickAction
    public let placement: MenuPlacement

    public init(action: RightClickAction, placement: MenuPlacement) {
        self.action = action
        self.placement = placement
    }

    public var menuTag: Int {
        EncodedMenuItemPayload(
            value: FixedActionTagValue(action: action),
            placement: placement
        ).menuTag
    }

    public init?(menuTag: Int) {
        guard let payload = EncodedMenuItemPayload<FixedActionTagValue>(
            menuTag: menuTag
        ) else { return nil }
        self.init(action: payload.value.action, placement: payload.placement)
    }
}

/// 动态 CLI 使用 501...900；命令与参数不进入 tag 或 URL。
public struct ConfiguredCLIMenuItemPayload: Equatable, Sendable {
    public let menuSlot: Int
    public let placement: MenuPlacement

    public init(menuSlot: Int, placement: MenuPlacement) {
        self.menuSlot = menuSlot
        self.placement = placement
    }

    public var menuTag: Int {
        EncodedMenuItemPayload(
            value: MenuSlotTagValue<ConfiguredCLITagSegment>(slot: menuSlot),
            placement: placement
        ).menuTag
    }

    public init?(menuTag: Int) {
        guard let payload = EncodedMenuItemPayload<
            MenuSlotTagValue<ConfiguredCLITagSegment>
        >(menuTag: menuTag) else { return nil }
        self.init(menuSlot: payload.value.slot, placement: payload.placement)
    }
}

/// 自定义模板使用 101...400；文件名和内容只从 0600 镜像读取。
public struct CustomTemplateMenuItemPayload: Equatable, Sendable {
    public let menuSlot: Int
    public let placement: MenuPlacement

    public init(menuSlot: Int, placement: MenuPlacement) {
        self.menuSlot = menuSlot
        self.placement = placement
    }

    public var menuTag: Int {
        EncodedMenuItemPayload(
            value: MenuSlotTagValue<CustomTemplateTagSegment>(slot: menuSlot),
            placement: placement
        ).menuTag
    }

    public init?(menuTag: Int) {
        guard let payload = EncodedMenuItemPayload<
            MenuSlotTagValue<CustomTemplateTagSegment>
        >(menuTag: menuTag) else { return nil }
        self.init(menuSlot: payload.value.slot, placement: payload.placement)
    }
}

extension MenuPlacement {
    var menuTagCode: Int {
        switch self {
        case .items: 1
        case .container: 2
        case .sidebar: 3
        case .toolbar: 4
        }
    }

    init?(menuTagCode: Int) {
        switch menuTagCode {
        case 1: self = .items
        case 2: self = .container
        case 3: self = .sidebar
        case 4: self = .toolbar
        default: return nil
        }
    }
}
