import Foundation

public struct SelectionContext: Equatable, Sendable {
    public let selectedURLs: [URL]
    public let targetedURL: URL?

    /// 判断目录要走文件系统，而每次右键都会重新构建菜单，且菜单构建期的
    /// 每一次探测都直接体现为 Finder 弹出菜单的延迟（网络卷上尤其明显）。
    /// 因此这些派生值在初始化时算一次并缓存，而不是每次访问都重新探测。
    public let effectiveURLs: [URL]
    public let creationDirectory: URL?
    public let workingDirectory: URL?

    public init(selectedURLs: [URL], targetedURL: URL?) {
        self.selectedURLs = selectedURLs
        self.targetedURL = targetedURL

        let effectiveURLs = selectedURLs.isEmpty
            ? targetedURL.map { [$0] } ?? []
            : selectedURLs
        self.effectiveURLs = effectiveURLs

        var probed: [URL: Bool] = [:]
        func isEnterableDirectory(_ url: URL) -> Bool {
            if let cached = probed[url] { return cached }
            let result = Self.probeIsEnterableDirectory(url)
            probed[url] = result
            return result
        }
        func directoryRepresented(by url: URL) -> URL {
            isEnterableDirectory(url) ? url : url.deletingLastPathComponent()
        }

        if selectedURLs.isEmpty {
            creationDirectory = targetedURL.map(directoryRepresented(by:))
        } else if selectedURLs.count == 1,
                  let selected = selectedURLs.first,
                  isEnterableDirectory(selected) {
            creationDirectory = selected
        } else {
            creationDirectory = selectedURLs.first?.deletingLastPathComponent()
        }

        workingDirectory = effectiveURLs.first.map(directoryRepresented(by:))
    }

    /// 包（.app / .xcodeproj / .rtfd / …）在磁盘上是目录，但 Finder 把它当成
    /// 一个文件。新建文件和终端目录若进入包内部，会破坏签名或污染工程。
    private static func probeIsEnterableDirectory(_ url: URL) -> Bool {
        probeIsDirectory(url) && !probeIsPackage(url)
    }

    private static func probeIsPackage(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) ?? false
    }

    private static func probeIsDirectory(_ url: URL) -> Bool {
        if let value = try? url.resourceValues(
            forKeys: [.isDirectoryKey]
        ).isDirectory {
            return value
        }

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        ) {
            return isDirectory.boolValue
        }

        return url.hasDirectoryPath
    }
}
