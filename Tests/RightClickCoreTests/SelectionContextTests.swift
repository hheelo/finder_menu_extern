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
    func usesParentDirectoryWhenMultipleItemsAreSelected() {
        let folder = URL(fileURLWithPath: "/tmp/example", isDirectory: true)
        let sibling = URL(fileURLWithPath: "/tmp/other.txt")
        let context = SelectionContext(
            selectedURLs: [folder, sibling],
            targetedURL: nil
        )

        #expect(context.effectiveURLs == [folder, sibling])
        #expect(context.creationDirectory?.path == "/tmp")
        #expect(context.workingDirectory?.path == "/tmp/example")
    }

    @Test
    func hasNoDirectoriesWithoutSelectionOrTarget() {
        let context = SelectionContext(selectedURLs: [], targetedURL: nil)

        #expect(context.effectiveURLs.isEmpty)
        #expect(context.creationDirectory == nil)
        #expect(context.workingDirectory == nil)
    }

    @Test
    func quotesShellPathsSafely() {
        let value = ShellCommandBuilder.quote("/tmp/Alice's Project")
        #expect(value == "'/tmp/Alice'\\''s Project'")
    }

    @Test
    func detectsExistingDirectoryWithoutTrailingSlash() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let urlWithoutDirectoryHint = URL(fileURLWithPath: directory.path)
        let context = SelectionContext(
            selectedURLs: [urlWithoutDirectoryHint],
            targetedURL: nil
        )

        #expect(context.creationDirectory?.path == directory.path)
        #expect(context.workingDirectory?.path == directory.path)
    }
}
