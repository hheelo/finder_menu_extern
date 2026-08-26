import Foundation

/// Finder 扩展请求未沙箱化宿主在目标目录中创建文件。
///
/// Finder 提供的 `targetedURL` 只描述上下文，并不会授予沙箱扩展写权限；因此
/// 创建动作与启动外部 App 一样，必须通过经过认证的深链交给宿主执行。
public struct FileCreationInvocation: Equatable, SignedInvocation, Sendable {
    public enum Request: Equatable, Sendable {
        case builtInTemplate(FileTemplate)
        case folder
        case clipboardText
        case customTemplate(menuSlot: Int)
    }

    public static let deepLinkHost = "create"

    public let request: Request
    public let directory: URL
    public let authenticationToken: String?

    public init(
        request: Request,
        directory: URL,
        authenticationToken: String? = nil
    ) {
        self.request = request
        self.directory = directory
        self.authenticationToken = authenticationToken
    }

    public var deepLinkQueryItems: [URLQueryItem]? {
        guard DeepLinkComponents.validWorkingDirectory(directory) else {
            return nil
        }
        var items = [URLQueryItem(name: "path", value: directory.path)]
        switch request {
        case let .builtInTemplate(template):
            items += [
                URLQueryItem(name: "kind", value: "built-in"),
                URLQueryItem(name: "template", value: template.rawValue)
            ]
        case .folder:
            items.append(URLQueryItem(name: "kind", value: "folder"))
        case .clipboardText:
            items.append(URLQueryItem(name: "kind", value: "clipboard"))
        case let .customTemplate(menuSlot):
            guard CustomFileTemplate.validMenuSlots.contains(menuSlot) else {
                return nil
            }
            items += [
                URLQueryItem(name: "kind", value: "custom"),
                URLQueryItem(name: "slot", value: String(menuSlot))
            ]
        }
        return items
    }

    public init?(
        deepLink: URL,
        fileManager: FileManager = .default
    ) {
        guard let components = DeepLinkComponents.authenticated(
            deepLink: deepLink,
            host: Self.deepLinkHost,
            semanticNames: ["path", "kind", "template", "slot"]
        ),
        let directory = components.existingAbsoluteDirectory(
            "path",
            fileManager: fileManager
        ),
        let kind = components.single("kind") else {
            return nil
        }

        let request: Request
        switch kind {
        case "built-in":
            guard components.single("slot") == nil,
                  let rawTemplate = components.single("template"),
                  let template = FileTemplate(rawValue: rawTemplate) else {
                return nil
            }
            request = .builtInTemplate(template)
        case "folder":
            guard components.single("template") == nil,
                  components.single("slot") == nil else { return nil }
            request = .folder
        case "clipboard":
            guard components.single("template") == nil,
                  components.single("slot") == nil else { return nil }
            request = .clipboardText
        case "custom":
            guard components.single("template") == nil,
                  let rawSlot = components.single("slot"),
                  let slot = Int(rawSlot),
                  CustomFileTemplate.validMenuSlots.contains(slot) else {
                return nil
            }
            request = .customTemplate(menuSlot: slot)
        default:
            return nil
        }

        self.request = request
        self.directory = directory
        authenticationToken = nil
    }

    /// 相等性表示「要创建的内容与位置」相同，不比较传输层认证封装。
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.request == rhs.request && lhs.directory == rhs.directory
    }
}
