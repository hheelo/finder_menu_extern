import Foundation
import Testing
@testable import RightClickCore

struct RelativePathResolverTests {
    /// 用注入的存在性判定代替真实文件系统：仓库根固定为 /tmp/repo。
    private let repoOnly: (String) -> Bool = { $0 == "/tmp/repo/.git" }
    private let nothingExists: (String) -> Bool = { _ in false }

    @Test
    func findsNearestRepositoryRoot() {
        #expect(
            RelativePathResolver.repositoryRoot(
                for: URL(fileURLWithPath: "/tmp/repo/a/b"),
                itemExists: repoOnly
            ) == URL(fileURLWithPath: "/tmp/repo")
        )
        // 目录本身就是仓库根。
        #expect(
            RelativePathResolver.repositoryRoot(
                for: URL(fileURLWithPath: "/tmp/repo"),
                itemExists: repoOnly
            ) == URL(fileURLWithPath: "/tmp/repo")
        )
    }

    /// 沙箱拒绝读取与「确实不在仓库里」在这一层无法区分，两者都必须终止于根
    /// 目录并返回 nil，而不是无限向上走。
    @Test
    func stopsAtRootWhenNothingIsReadable() {
        #expect(
            RelativePathResolver.repositoryRoot(
                for: URL(fileURLWithPath: "/tmp/a/b/c"),
                itemExists: nothingExists
            ) == nil
        )
        #expect(
            RelativePathResolver.repositoryRoot(
                for: URL(fileURLWithPath: "/"),
                itemExists: nothingExists
            ) == nil
        )
    }

    @Test
    func computesRelativePathsAndRejectsOutsiders() {
        let base = URL(fileURLWithPath: "/tmp/repo")
        #expect(
            RelativePathResolver.relativePath(
                of: URL(fileURLWithPath: "/tmp/repo/a/b.txt"),
                from: base
            ) == "a/b.txt"
        )
        // 选中的就是基准目录本身。
        #expect(
            RelativePathResolver.relativePath(of: base, from: base) == "."
        )
        // 基准之外不生成 ../，交给调用方回退绝对路径。
        #expect(
            RelativePathResolver.relativePath(
                of: URL(fileURLWithPath: "/tmp/other/b.txt"),
                from: base
            ) == nil
        )
        // 同名前缀不算祖先：/tmp/repo2 不在 /tmp/repo 之下。
        #expect(
            RelativePathResolver.relativePath(
                of: URL(fileURLWithPath: "/tmp/repo2/b.txt"),
                from: base
            ) == nil
        )
    }

    @Test
    func prefersRepositoryRootThenFallsBackToWindowDirectory() {
        let context = SelectionContext(
            selectedURLs: [URL(fileURLWithPath: "/tmp/repo/a/b.txt")],
            targetedURL: URL(fileURLWithPath: "/tmp/repo/a")
        )
        #expect(
            RelativePathResolver.base(for: context, itemExists: repoOnly)
                == URL(fileURLWithPath: "/tmp/repo")
        )
        // 不在仓库里时退到 Finder 当前窗口目录，而不是让动作失败。
        #expect(
            RelativePathResolver.base(for: context, itemExists: nothingExists)
                == URL(fileURLWithPath: "/tmp/repo/a")
        )
    }

    @Test
    func copiesRelativePathsAndFallsBackToAbsoluteOutsideBase() {
        let text = ClipboardText.relativePaths(
            for: [
                URL(fileURLWithPath: "/tmp/repo/a/b.txt"),
                URL(fileURLWithPath: "/tmp/other/c.txt")
            ],
            base: URL(fileURLWithPath: "/tmp/repo")
        )
        #expect(text == "a/b.txt\n/tmp/other/c.txt")
    }

    /// 基准解析失败时必须返回 nil，让扩展抛出可上报的错误——绝不能悄悄
    /// 退化成绝对路径，那会让用户粘错内容却毫无察觉。
    @Test
    func relativeCopyWithoutBaseYieldsNil() {
        #expect(
            ClipboardText.text(
                for: .copyRelativePath,
                urls: [URL(fileURLWithPath: "/tmp/a.txt")],
                base: nil
            ) == nil
        )
    }
}
