import Foundation

public enum AppConstants {
    public static let deepLinkScheme = "rightclick"
    public static let finderExtensionBundleIdentifier =
        "com.hheelo.RightClick.FinderExtension"

    /// `pluginkit -m` 每一行开头的标记表示用户选择状态：`+` 是启用，
    /// `!` 是调试时启用。这个解析用于 macOS 14.0–14.3；14.4 起系统提供了
    /// `FIFinderSyncController.isExtensionEnabled`，不再需要命令行兜底。
    public static func plugInKitOutputIndicatesEnabled(_ output: String) -> Bool {
        output.split(whereSeparator: \.isNewline).contains { line in
            guard let marker = line.first(where: { !$0.isWhitespace }) else {
                return false
            }
            return marker == "+" || marker == "!"
        }
    }
}
