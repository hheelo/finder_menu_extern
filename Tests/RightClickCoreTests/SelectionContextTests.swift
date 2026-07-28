import Foundation
import Testing
@testable import RightClickCore

struct SelectionContextTests {
    @Test
    func usesTargetedFolderForBackgroundMenu() {
        let folder = URL(fileURLWithPath: "/tmp/example", isDirectory: true)
        let context = SelectionContext(selectedURLs: [], targetedURL: folder)
        #expect(context.creationDirectory == folder)
    }

    @Test
    func usesSelectedFolderAsCreationDirectory() {
        let folder = URL(fileURLWithPath: "/tmp/example", isDirectory: true)
        let context = SelectionContext(
            selectedURLs: [folder],
            targetedURL: folder
        )
        #expect(context.creationDirectory == folder)
    }

    @Test
    func quotesShellPathsSafely() {
        let value = ShellCommandBuilder.quote("/tmp/Alice's Project")
        #expect(value == "'/tmp/Alice'\\''s Project'")
    }
}
