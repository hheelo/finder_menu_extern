import Foundation
import RightClickCore

/// 把 Finder 的瞬时选区快照转换为 Core 上下文。调用方必须只在菜单构建或点击
/// 回调期间读取 Finder controller，再把值一次性交给这里。
public enum FinderSelectionResolver {
    public static func context(
        placement: MenuPlacement,
        selectedURLs: [URL],
        targetedURL: URL?
    ) -> SelectionContext {
        SelectionContext(
            selectedURLs: placement.usesTargetedURLOnly ? [] : selectedURLs,
            targetedURL: targetedURL
        )
    }
}
