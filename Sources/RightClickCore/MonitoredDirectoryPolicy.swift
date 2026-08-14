import Foundation

/// Finder Sync 监控范围的跨进程规则。
///
/// 配置只保存绝对、标准化且去重的路径；目录是否仍存在必须由扩展启动时复核，
/// 因为外置盘可能在宿主保存配置之后被拔出。空配置或全部不可用时回退 `/`，
/// 不能让一份损坏或过时的配置使整个 RightClick 菜单消失。
public enum MonitoredDirectoryPolicy {
    public static let fallbackURL = URL(
        fileURLWithPath: "/",
        isDirectory: true
    )

    public static func sanitizedPaths(_ paths: [String]) -> [String] {
        var seen: Set<String> = []
        return paths.compactMap { path in
            guard path.hasPrefix("/"), !path.contains("\0") else { return nil }
            let standardized = URL(
                fileURLWithPath: path,
                isDirectory: true
            ).standardizedFileURL.path
            guard seen.insert(standardized).inserted else { return nil }
            return standardized
        }
    }

    public static func resolvedURLs(
        _ paths: [String],
        isDirectory: (String) -> Bool
    ) -> Set<URL> {
        let existing = sanitizedPaths(paths).compactMap { path -> URL? in
            guard isDirectory(path) else { return nil }
            return URL(fileURLWithPath: path, isDirectory: true)
                .standardizedFileURL
        }
        return existing.isEmpty ? [fallbackURL] : Set(existing)
    }
}
