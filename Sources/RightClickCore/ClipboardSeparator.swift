import Foundation

/// 多选复制时各项之间的分隔方式。
///
/// 复制发生在 Finder 扩展进程里，所以这个设置必须随 ``MenuConfiguration`` 一起
/// 下发到扩展容器——扩展读不到宿主的 UserDefaults。
public enum ClipboardSeparator: String, Codable, CaseIterable, Sendable {
    case newline
    case space
    case comma

    public var title: String {
        switch self {
        case .newline: "换行"
        case .space: "空格"
        case .comma: "逗号"
        }
    }

    public var text: String {
        switch self {
        case .newline: "\n"
        case .space: " "
        case .comma: ", "
        }
    }
}
