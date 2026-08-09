import Foundation

/// 一个 `NSMenuItem.tag` 解码后的三种可能。
///
/// 三类 payload 的动作码占用互不重叠的区段：固定动作 1...100、自定义模板
/// 101...400、动态 CLI 501...900。解码顺序即优先级，改动这里之前先确认区段划分
/// 没有变——`MenuItemPayloadTests` 会守住这个不变量。
public enum MenuItemPayload: Equatable, Sendable {
    case action(RightClickMenuItemPayload)
    case configuredCLI(ConfiguredCLIMenuItemPayload)
    case customTemplate(CustomTemplateMenuItemPayload)

    public init?(menuTag: Int) {
        if let configured = ConfiguredCLIMenuItemPayload(menuTag: menuTag) {
            self = .configuredCLI(configured)
        } else if let template = CustomTemplateMenuItemPayload(
            menuTag: menuTag
        ) {
            self = .customTemplate(template)
        } else if let action = RightClickMenuItemPayload(menuTag: menuTag) {
            self = .action(action)
        } else {
            return nil
        }
    }

    public var placement: MenuPlacement {
        switch self {
        case let .action(payload): payload.placement
        case let .configuredCLI(payload): payload.placement
        case let .customTemplate(payload): payload.placement
        }
    }
}
