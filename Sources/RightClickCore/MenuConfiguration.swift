import Foundation

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
    public var actionOrder: [String]
    public var collapseIntoSubmenu: Bool
    /// 扩展用它判断所选终端是否具备运行 CLI 的能力；nil 等同 automatic。
    public var terminalProfileID: String?
    public var cliProfiles: [CLIProfile]
    public var customTemplates: [CustomFileTemplate]

    public init(
        version: Int = currentVersion,
        disabledActions: Set<String> = [],
        actionOrder: [String] = [],
        collapseIntoSubmenu: Bool = false,
        terminalProfileID: String? = nil,
        cliProfiles: [CLIProfile] = [],
        customTemplates: [CustomFileTemplate] = []
    ) {
        self.version = version
        self.disabledActions = disabledActions
        self.actionOrder = actionOrder
        self.collapseIntoSubmenu = collapseIntoSubmenu
        self.terminalProfileID = terminalProfileID
        self.cliProfiles = cliProfiles
        self.customTemplates = customTemplates
    }

    public static let `default` = MenuConfiguration()

    private enum CodingKeys: String, CodingKey {
        case version, disabledActions, actionOrder, collapseIntoSubmenu
        case terminalProfileID, cliProfiles, customTemplates
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
        cliProfiles = try values.decodeIfPresent(
            [CLIProfile].self,
            forKey: .cliProfiles
        ) ?? []
        customTemplates = try values.decodeIfPresent(
            [CustomFileTemplate].self,
            forKey: .customTemplates
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
        return copy
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

    public var isValid: Bool {
        let executableCharacters = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._+-"
        )
        return Self.isValidID(id)
            && (1...64).contains(title.count)
            && !title.contains("\n")
            && (1...128).contains(executable.count)
            && executable.unicodeScalars.allSatisfy(executableCharacters.contains)
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
