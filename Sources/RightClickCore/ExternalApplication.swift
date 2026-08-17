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
    private let memoizedCandidateURLs: [URL]

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
        memoizedCandidateURLs = Self.searchRoots.flatMap { root in
            names.map {
                root.appendingPathComponent("\($0).app", isDirectory: true)
            }
        }
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
        memoizedCandidateURLs
    }
}

public extension ExternalApplication {
    static let visualStudioCode = ExternalApplication(
        identifier: "vscode",
        title: "Visual Studio Code",
        bundleIdentifiers: ["com.microsoft.VSCode"],
        names: ["Visual Studio Code"]
    )

    // `identifier` 是已发布的深链契约，继续保留 codex；用户可见名称按实际
    // 应用显示为 ChatGPT。旧安装若仍叫 Codex，目录回退也继续兼容。
    static let codex = ExternalApplication(
        identifier: "codex",
        title: "ChatGPT",
        bundleIdentifiers: ["com.openai.codex"],
        names: ["ChatGPT", "Codex"]
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

    static let warp = ExternalApplication(
        identifier: "warp",
        title: "Warp",
        bundleIdentifiers: ["dev.warp.Warp-Stable", "dev.warp.Warp-Preview"],
        names: ["Warp", "WarpPreview"]
    )

    static let ghostty = ExternalApplication(
        identifier: "ghostty",
        title: "Ghostty",
        bundleIdentifiers: ["com.mitchellh.ghostty"],
        names: ["Ghostty"]
    )

    static let wezTerm = ExternalApplication(
        identifier: "wezterm",
        title: "WezTerm",
        bundleIdentifiers: ["com.github.wez.wezterm"],
        names: ["WezTerm"]
    )

    static let kitty = ExternalApplication(
        identifier: "kitty",
        title: "kitty",
        bundleIdentifiers: ["net.kovidgoyal.kitty"],
        names: ["kitty"]
    )

    static let cursor = ExternalApplication(
        identifier: "cursor",
        title: "Cursor",
        bundleIdentifiers: ["com.todesktop.230313mzl4w4u92"],
        names: ["Cursor"]
    )

    static let zed = ExternalApplication(
        identifier: "zed",
        title: "Zed",
        bundleIdentifiers: ["dev.zed.Zed", "dev.zed.Zed-Preview"],
        names: ["Zed", "Zed Preview"]
    )

    static let sublimeText = ExternalApplication(
        identifier: "sublime-text",
        title: "Sublime Text",
        bundleIdentifiers: ["com.sublimetext.4", "com.sublimetext.3"],
        names: ["Sublime Text"]
    )

    static let xcode = ExternalApplication(
        identifier: "xcode",
        title: "Xcode",
        bundleIdentifiers: ["com.apple.dt.Xcode"],
        names: ["Xcode"]
    )

    static let jetBrains = ExternalApplication(
        identifier: "jetbrains",
        title: "JetBrains IDE",
        bundleIdentifiers: [
            "com.jetbrains.intellij", "com.jetbrains.WebStorm",
            "com.jetbrains.PyCharm", "com.jetbrains.CLion",
            "com.jetbrains.goland", "com.jetbrains.rider",
            "com.jetbrains.RubyMine", "com.jetbrains.datagrip"
        ],
        names: [
            "IntelliJ IDEA", "WebStorm", "PyCharm", "CLion", "GoLand",
            "Rider", "RubyMine", "DataGrip"
        ]
    )

    /// 宿主把这个稳定标识解释为 `NSWorkspace` 的系统默认处理程序；没有
    /// Bundle ID，因而不能走普通的应用定位分支。
    static let systemDefault = ExternalApplication(
        identifier: "system-default",
        title: L10n.text("app.default_application", fallback: "默认应用"),
        bundleIdentifiers: [],
        names: []
    )

    /// 深链只接受这里列出的 App，避免宿主被诱导去启动任意程序。
    static let known: [ExternalApplication] = [
        .visualStudioCode, .codex, .terminal, .iTerm,
        .warp, .ghostty, .wezTerm, .kitty,
        .cursor, .zed, .sublimeText, .xcode, .jetBrains, .systemDefault
    ]

    /// 「用 X 打开」动作到白名单条目的唯一映射；其他动作返回 nil。
    ///
    /// 放在 Core 而不是扩展的 switch 里：新增 `openIn*` 动作却忘了接线时，
    /// `ExternalApplicationTests` 会报红，而扩展 target 没有测试。
    static func forOpenAction(
        _ action: RightClickAction
    ) -> ExternalApplication? {
        switch action {
        case .openInVSCode: .visualStudioCode
        case .openInCodex: .codex
        case .openInCursor: .cursor
        case .openInZed: .zed
        case .openInSublimeText: .sublimeText
        case .openInXcode: .xcode
        case .openInJetBrains: .jetBrains
        case .openInDefaultApplication: .systemDefault
        case .copyPath, .copyFilename, .copyFileURL, .copyShellPath,
             .copyParentPath, .copyRelativePath, .openInTerminal,
             .runCodexCLI, .runClaudeCode, .createFile, .createFolder,
             .createFileFromClipboard:
            nil
        }
    }

    init?(identifier: String) {
        guard let match = Self.known.first(
            where: { $0.identifier == identifier }
        ) else {
            return nil
        }
        self = match
    }
}
