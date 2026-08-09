import Foundation
import Testing
@testable import RightClickCore

struct ClipboardTextTests {
    private let urls = [
        URL(fileURLWithPath: "/tmp/Alice's Project/file one.txt"),
        URL(fileURLWithPath: "/tmp/中文/二.txt")
    ]

    @Test
    func copiesFileURLs() {
        #expect(
            ClipboardText.fileURLs(for: urls)
                == "file:///tmp/Alice's%20Project/file%20one.txt\nfile:///tmp/%E4%B8%AD%E6%96%87/%E4%BA%8C.txt"
        )
    }

    @Test
    func copiesShellQuotedPaths() {
        #expect(
            ClipboardText.shellQuotedPaths(for: urls)
                == "'/tmp/Alice'\\''s Project/file one.txt'\n'/tmp/中文/二.txt'"
        )
    }

    @Test
    func copiesParentPaths() {
        #expect(
            ClipboardText.parentPaths(for: urls)
                == "/tmp/Alice's Project\n/tmp/中文"
        )
    }

    @Test
    func honoursTheConfiguredSeparator() {
        #expect(
            ClipboardText.paths(for: urls, separator: .comma)
                == "/tmp/Alice's Project/file one.txt, /tmp/中文/二.txt"
        )
        #expect(
            ClipboardText.filenames(for: urls, separator: .space)
                == "file one.txt 二.txt"
        )
    }

    /// 非复制动作必须返回 nil，否则扩展会把空串塞进剪贴板。
    @Test
    func mapsOnlyClipboardActionsToText() {
        for action in RightClickAction.allMenuActions {
            let text = ClipboardText.text(
                for: action,
                urls: urls,
                base: URL(fileURLWithPath: "/tmp")
            )
            let isClipboardAction = action.logDescription.hasPrefix("copy")
            #expect((text != nil) == isClipboardAction)
        }
    }
}
