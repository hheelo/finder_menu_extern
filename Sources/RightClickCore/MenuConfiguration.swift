import Foundation

public enum TemplateEncoding: String, CaseIterable, Codable, Sendable {
    case utf8 = "utf-8"
    case utf8BOM = "utf-8-bom"
    case utf16 = "utf-16"

    public var title: String {
        switch self {
        case .utf8:
            L10n.text("template.encoding.utf8", fallback: "UTF-8")
        case .utf8BOM:
            L10n.text("template.encoding.utf8_bom", fallback: "UTF-8（带 BOM）")
        case .utf16:
            L10n.text("template.encoding.utf16", fallback: "UTF-16")
        }
    }

    public func encode(_ value: String) -> Data {
        switch self {
        case .utf8:
            Data(value.utf8)
        case .utf8BOM:
            Data([0xEF, 0xBB, 0xBF]) + Data(value.utf8)
        case .utf16:
            value.data(using: .utf16) ?? Data([0xFF, 0xFE])
        }
    }
}

public struct TemplateOverride: Codable, Equatable, Sendable {
    public var filename: String?
    /// 保留字符串而不是直接存枚举，让未来版本新增编码时旧扩展可以安全回退。
    public var encoding: String?

    public init(filename: String? = nil, encoding: String? = nil) {
        self.filename = filename
        self.encoding = encoding
    }

    public var resolvedEncoding: TemplateEncoding {
        encoding.flatMap(TemplateEncoding.init(rawValue:)) ?? .utf8
    }

    var sanitized: TemplateOverride? {
        let safeFilename = filename.flatMap {
            FileCreator.isSafeFilename($0) ? $0 : nil
        }
        let safeEncoding = encoding.flatMap(TemplateEncoding.init(rawValue:))?
            .rawValue
        guard safeFilename != nil || safeEncoding != nil else { return nil }
        return TemplateOverride(
            filename: safeFilename,
            encoding: safeEncoding
        )
    }
}

/// 宿主与 Finder 扩展之间的菜单配置契约。
///
/// - 配置缺失、损坏或版本未知时必须回退 ``default``，不能让 Finder 菜单消失。
/// - 排序只使用稳定的 `configurationID`；`menuTag` 仍由
///   `RightClickAction.allMenuActions` 的发布顺序决定，两者不能混用。
/// - 文件由未沙箱化宿主写入且权限固定为 0600；Finder 扩展只读。
/// - 扩展每次构建菜单都重新读取文件，不缓存配置。
public struct MenuConfiguration: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var disabledActions: Set<String>
    /// 只包含内置 `RightClickAction.configurationID`。动态 CLI 与模板按各自稳定的
    /// menuSlot 排列，不叠加第二套 actionOrder 顺序。
    public var actionOrder: [String]
    public var collapseIntoSubmenu: Bool
    /// 扩展用它判断所选终端是否具备运行 CLI 的能力；nil 等同 automatic。
    public var terminalProfileID: String?
    /// 多选复制时的分隔方式；nil 或无法识别的值等同换行。
    ///
    /// 存 `String?` 而不是枚举：这个文件是跨版本、跨进程的输入，旧扩展遇到
    /// 将来新增的分隔方式必须能降级，而不是整份配置解码失败。
    public var copySeparator: String?
    public var cliProfiles: [CLIProfile]
    public var customTemplates: [CustomFileTemplate]
    /// key 为 `FileTemplate.rawValue`；非法 key 或覆盖值在加载时被忽略。
    public var templateOverrides: [String: TemplateOverride]
    /// Finder Sync 启动时读取的监控目录。空数组表示监控 `/`，保持旧版本行为。
    /// 修改后必须重启 Finder；Apple 要求扩展在启动时设置 `directoryURLs`。
    public var monitoredDirectories: [String]

    public init(
        version: Int = currentVersion,
        disabledActions: Set<String> = [],
        actionOrder: [String] = [],
        collapseIntoSubmenu: Bool = false,
        terminalProfileID: String? = nil,
        copySeparator: String? = nil,
        cliProfiles: [CLIProfile] = [],
        customTemplates: [CustomFileTemplate] = [],
        templateOverrides: [String: TemplateOverride] = [:],
        monitoredDirectories: [String] = []
    ) {
        self.version = version
        self.disabledActions = disabledActions
        self.actionOrder = actionOrder
        self.collapseIntoSubmenu = collapseIntoSubmenu
        self.terminalProfileID = terminalProfileID
        self.copySeparator = copySeparator
        self.cliProfiles = cliProfiles
        self.customTemplates = customTemplates
        self.templateOverrides = templateOverrides
        self.monitoredDirectories = monitoredDirectories
    }

    /// 解析后的分隔方式。未设置或无法识别时回退换行。
    public var clipboardSeparator: ClipboardSeparator {
        copySeparator.flatMap(ClipboardSeparator.init(rawValue:)) ?? .newline
    }

    public static let `default` = MenuConfiguration()

    private enum CodingKeys: String, CodingKey {
        case version, disabledActions, actionOrder, collapseIntoSubmenu
        case terminalProfileID, copySeparator, cliProfiles, customTemplates
        case templateOverrides, monitoredDirectories
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        disabledActions = try values.decodeIfPresent(
            Set<String>.self,
            forKey: .disabledActions
        ) ?? []
        actionOrder = try values.decodeIfPresent(
            [String].self,
            forKey: .actionOrder
        ) ?? []
        collapseIntoSubmenu = try values.decodeIfPresent(
            Bool.self,
            forKey: .collapseIntoSubmenu
        ) ?? false
        terminalProfileID = try values.decodeIfPresent(
            String.self,
            forKey: .terminalProfileID
        )
        copySeparator = try values.decodeIfPresent(
            String.self,
            forKey: .copySeparator
        )
        cliProfiles = try values.decodeIfPresent(
            [CLIProfile].self,
            forKey: .cliProfiles
        ) ?? []
        customTemplates = try values.decodeIfPresent(
            [CustomFileTemplate].self,
            forKey: .customTemplates
        ) ?? []
        templateOverrides = try values.decodeIfPresent(
            [String: TemplateOverride].self,
            forKey: .templateOverrides
        ) ?? [:]
        monitoredDirectories = try values.decodeIfPresent(
            [String].self,
            forKey: .monitoredDirectories
        ) ?? []
    }

    /// 忽略无效或重复动态项，基础菜单配置仍然可用。
    public var sanitized: MenuConfiguration {
        var copy = self
        var ids: Set<String> = []
        var slots: Set<Int> = []
        copy.cliProfiles = cliProfiles.filter { profile in
            profile.isValid && ids.insert(profile.id).inserted
                && slots.insert(profile.menuSlot).inserted
        }
        ids.removeAll(keepingCapacity: true)
        slots.removeAll(keepingCapacity: true)
        copy.customTemplates = customTemplates.filter { template in
            template.isValid && ids.insert(template.id).inserted
                && slots.insert(template.menuSlot).inserted
        }
        copy.templateOverrides = templateOverrides.reduce(into: [:]) {
            result, element in
            guard FileTemplate(rawValue: element.key) != nil,
                  let sanitized = element.value.sanitized else { return }
            result[element.key] = sanitized
        }
        copy.monitoredDirectories = MonitoredDirectoryPolicy.sanitizedPaths(
            monitoredDirectories
        )
        return copy
    }

    /// 点击动态 CLI 菜单项时按 slot 重新查配置。
    ///
    /// 命令和参数只存在于这份 0600 文件里，既不进 tag 也不进 URL；配置在菜单
    /// 弹出后被删除或禁用时返回 nil，由调用方当成一次失败处理。
    public func cliProfile(forSlot slot: Int) -> CLIProfile? {
        cliProfiles.first {
            $0.menuSlot == slot && $0.isEnabled && $0.isValid
        }
    }

    public func customTemplate(forSlot slot: Int) -> CustomFileTemplate? {
        customTemplates.first { $0.menuSlot == slot && $0.isValid }
    }

    public func templateOverride(for template: FileTemplate) -> TemplateOverride? {
        templateOverrides[template.rawValue]?.sanitized
    }
}

public struct CustomFileTemplate: Codable, Equatable, Identifiable, Sendable {
    public static let validMenuSlots = 1...300

    public var id: String
    public var title: String
    public var filename: String
    public var menuSlot: Int

    public init(id: String, title: String, filename: String, menuSlot: Int) {
        self.id = id
        self.title = title
        self.filename = filename
        self.menuSlot = menuSlot
    }

    public var configurationID: String { "template:\(id)" }

    public var isValid: Bool {
        CLIProfile.isValidID(id)
            && (1...128).contains(title.count)
            && !title.contains("\n")
            && FileCreator.isSafeFilename(filename)
            && Self.validMenuSlots.contains(menuSlot)
    }
}

public struct CLIProfile: Codable, Equatable, Identifiable, Sendable {
    public static let validMenuSlots = 1...400

    public var id: String
    public var title: String
    public var executable: String
    public var arguments: [String]
    public var menuSlot: Int
    public var isEnabled: Bool

    public init(
        id: String,
        title: String,
        executable: String,
        arguments: [String] = [],
        menuSlot: Int,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.executable = executable
        self.arguments = arguments
        self.menuSlot = menuSlot
        self.isEnabled = isEnabled
    }

    public var configurationID: String { "cli:\(id)" }

    public static func isValidID(_ id: String) -> Bool {
        let characters = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-"
        )
        return (1...64).contains(id.count)
            && id.unicodeScalars.allSatisfy(characters.contains)
    }

    /// 自定义 CLI 可以是 shell 能从 PATH 中解析的简单命令名，也可以是用户
    /// 明确填写的绝对路径。两种形式在执行前都会被逐项 shell quote；不接受
    /// 相对路径，避免配置的含义随 Finder/宿主进程的启动目录变化。
    public static func isValidExecutable(_ executable: String) -> Bool {
        guard (1...1024).contains(executable.count),
              !executable.contains("\0"),
              !executable.contains("\n") else {
            return false
        }

        if executable.contains("/") {
            return executable.hasPrefix("/")
                && executable != "/"
                && !executable.hasSuffix("/")
        }

        let executableCharacters = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._+-"
        )
        return executable.unicodeScalars.allSatisfy(executableCharacters.contains)
    }

    public var isValid: Bool {
        return Self.isValidID(id)
            && (1...64).contains(title.count)
            && !title.contains("\n")
            && Self.isValidExecutable(executable)
            && arguments.count <= 64
            && arguments.allSatisfy {
                $0.count <= 512 && !$0.contains("\0") && !$0.contains("\n")
            }
            && Self.validMenuSlots.contains(menuSlot)
    }
}

public enum MenuConfigurationFile {
    private static let supportDirectoryName = "RightClick"
    private static let filename = "menu.json"

    public static func load(from url: URL) -> MenuConfiguration {
        guard let data = try? Data(contentsOf: url),
              let configuration = try? JSONDecoder().decode(
                  MenuConfiguration.self,
                  from: data
              ), configuration.version == MenuConfiguration.currentVersion else {
            return .default
        }
        return configuration.sanitized
    }

    /// 只应由宿主调用。扩展 target 虽共享 Core，但运行时只走 ``load(from:)``。
    public static func saveForHost(
        _ configuration: MenuConfiguration,
        to url: URL,
        fileManager: FileManager = .default
    ) throws {
        guard configuration.version == MenuConfiguration.currentVersion else {
            throw MenuConfigurationFileError.unsupportedVersion
        }
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(configuration).write(to: url, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    public static func hostURL(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Containers", isDirectory: true)
            .appendingPathComponent(
                AppConstants.finderExtensionBundleIdentifier,
                isDirectory: true
            )
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(supportDirectoryName, isDirectory: true)
            .appendingPathComponent(filename, isDirectory: false)
    }

    public static func extensionURL(
        fileManager: FileManager = .default
    ) -> URL? {
        fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?
            .appendingPathComponent(supportDirectoryName, isDirectory: true)
            .appendingPathComponent(filename, isDirectory: false)
    }

    public static func hostTemplatesDirectory(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(supportDirectoryName, isDirectory: true)
            .appendingPathComponent("Templates", isDirectory: true)
    }

    public static func mirroredTemplatesDirectory(
        configurationURL: URL
    ) -> URL {
        configurationURL.deletingLastPathComponent()
            .appendingPathComponent("Templates", isDirectory: true)
    }
}

public enum MenuConfigurationFileError: Error, Equatable {
    case unsupportedVersion
}
