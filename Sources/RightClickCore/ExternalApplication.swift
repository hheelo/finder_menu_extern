import Foundation

/// 一个需要在系统里定位的外部 App。
///
/// Bundle ID、可执行名和搜索路径集中定义在这里：Finder 扩展的菜单动作和宿主
/// App 的环境诊断此前各有一份实现，搜索路径还不一致，会出现「诊断说没装、
/// 菜单却能打开」这种互相矛盾的结果。
public struct ExternalApplication: Equatable, Sendable {
    /// 深链里用来指代这个 App 的稳定标识，不随显示名变化。
    public let identifier: String
    public let title: String
    public let bundleIdentifiers: [String]
    public let names: [String]

    public init(
        identifier: String,
        title: String,
        bundleIdentifiers: [String],
        names: [String]
    ) {
        self.identifier = identifier
        self.title = title
        self.bundleIdentifiers = bundleIdentifiers
        self.names = names
    }

    /// 按 Bundle ID 找不到时回退搜索的目录。
    ///
    /// 注意：`homeDirectoryForCurrentUser` 在沙箱化的 Finder 扩展里指向容器，
    /// 因此 `~/Applications` 这一项对扩展基本无效；Bundle ID 查询才是主路径，
    /// 目录搜索只是 LaunchServices 数据库缺条目时的兜底。
    public static let searchRoots: [URL] = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true),
        URL(fileURLWithPath: "/System/Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
    ]

    /// 定位 App。
    ///
    /// Bundle ID 查询需要 AppKit（`NSWorkspace`），而 Core 不依赖 AppKit，
    /// 所以由调用方以闭包注入，目录回退和搜索顺序留在这里统一实现。
    public func url(
        bundleIdentifierLookup: (String) -> URL?,
        fileManager: FileManager = .default
    ) -> URL? {
        if let installed = bundleIdentifiers.lazy
            .compactMap(bundleIdentifierLookup)
            .first {
            return installed
        }

        return candidateURLs.first {
            fileManager.fileExists(atPath: $0.path)
        }
    }

    /// 目录回退时按「搜索路径 × 名称」展开的候选路径，顺序即优先级。
    public var candidateURLs: [URL] {
        Self.searchRoots.flatMap { root in
            names.map {
                root.appendingPathComponent("\($0).app", isDirectory: true)
            }
        }
    }
}

public extension ExternalApplication {
    static let visualStudioCode = ExternalApplication(
        identifier: "vscode",
        title: "Visual Studio Code",
        bundleIdentifiers: ["com.microsoft.VSCode"],
        names: ["Visual Studio Code"]
    )

    // 已核实：`com.openai.codex` 就是 ChatGPT.app 的 Bundle ID
    // （CFBundleName=ChatGPT，Codex 是其内部框架名）。所以这一项实际打开的是
    // ChatGPT.app，菜单标题「用 Codex 打开」可能需要按产品意图重新斟酌。
    static let codex = ExternalApplication(
        identifier: "codex",
        title: "Codex",
        bundleIdentifiers: ["com.openai.codex"],
        names: ["Codex"]
    )

    static let terminal = ExternalApplication(
        identifier: "terminal",
        title: "Terminal",
        bundleIdentifiers: ["com.apple.Terminal"],
        names: ["Terminal"]
    )

    static let iTerm = ExternalApplication(
        identifier: "iterm",
        title: "iTerm2",
        bundleIdentifiers: ["com.googlecode.iterm2"],
        names: ["iTerm", "iTerm2"]
    )

    /// 深链只接受这里列出的 App，避免宿主被诱导去启动任意程序。
    static let known: [ExternalApplication] = [
        .visualStudioCode, .codex, .terminal, .iTerm
    ]

    init?(identifier: String) {
        guard let match = Self.known.first(
            where: { $0.identifier == identifier }
        ) else {
            return nil
        }
        self = match
    }
}

public extension TerminalProfile {
    var application: ExternalApplication {
        switch self {
        case .terminal: .terminal
        case .iTerm: .iTerm
        }
    }
}
