import Foundation

/// 「复制相对路径」的基准目录解析。
///
/// 基准优先取所在 git 仓库根，其次取 Finder 当前窗口目录。仓库探测要读文件系统，
/// 因此只在用户真正点击动作时执行，绝不放进 `menu(for:)` —— 菜单构建期的每一次
/// 探测都直接体现为右键菜单的弹出延迟。
public enum RelativePathResolver {
    /// 向上查找 `.git` 的层数上限。
    ///
    /// 扩展被沙箱化，向上遍历可能在任意一层被拒绝；上限保证最坏情况下也只是多做
    /// 几次 stat，同时挡住符号链接构成的环。
    public static let maximumSearchDepth = 64

    /// 最近的含 `.git` 的祖先目录（含自身）。
    ///
    /// 找不到、或沙箱拒绝读取时返回 nil —— 两种情况在这一层无法区分，
    /// 也不需要区分：调用方一律降级到窗口目录，不让动作静默失败。
    public static func repositoryRoot(
        for directory: URL,
        itemExists: (String) -> Bool = {
            FileManager.default.fileExists(atPath: $0)
        }
    ) -> URL? {
        // 只做 standardize，不解析符号链接：复制出的路径必须和用户在 Finder
        // 里看到的是同一个，这与 `ClipboardText.fileURLs` 的既有行为一致。
        var current = directory.standardizedFileURL
        for _ in 0..<maximumSearchDepth {
            if itemExists(current.appendingPathComponent(".git").path) {
                // 统一用 `fileURLWithPath` 重建：`deletingLastPathComponent`
                // 会留下尾斜杠，而 URL 的相等性是按字符串比的，两种写法混用
                // 会让「同一个目录」在调用方比不相等。
                return URL(fileURLWithPath: current.path)
            }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            // 到达根目录后 `deletingLastPathComponent` 不再变化。
            guard parent.path != current.path else { return nil }
            current = parent
        }
        return nil
    }

    /// 相对路径的基准：git 仓库根 → Finder 窗口目录 → 工作目录。
    public static func base(
        for context: SelectionContext,
        itemExists: (String) -> Bool = {
            FileManager.default.fileExists(atPath: $0)
        }
    ) -> URL? {
        guard let start = context.workingDirectory else {
            return context.targetedURL.map { URL(fileURLWithPath: $0.path) }
        }
        if let root = repositoryRoot(for: start, itemExists: itemExists) {
            return root
        }
        return URL(fileURLWithPath: (context.targetedURL ?? start).path)
    }

    /// `base` 不是 `url` 的祖先时返回 nil，由调用方回退成绝对路径。
    ///
    /// 刻意不生成 `../../` 形式：多选跨越基准时，一份混着 `../` 和普通相对路径的
    /// 列表比直接给绝对路径更难读，也更容易被粘到错误的位置。
    public static func relativePath(of url: URL, from base: URL) -> String? {
        let target = url.standardizedFileURL.pathComponents
        let root = base.standardizedFileURL.pathComponents
        guard target.count >= root.count,
              Array(target.prefix(root.count)) == root else {
            return nil
        }
        let remainder = target.dropFirst(root.count)
        // 选中的就是基准目录本身。
        return remainder.isEmpty ? "." : remainder.joined(separator: "/")
    }
}
