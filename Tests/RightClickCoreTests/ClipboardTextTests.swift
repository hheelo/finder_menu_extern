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
}
