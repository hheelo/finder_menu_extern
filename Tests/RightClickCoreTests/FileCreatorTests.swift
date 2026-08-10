import Foundation
import Testing
@testable import RightClickCore

struct FileCreatorTests {
    @Test
    func createsTemplateAndAvoidsOverwriting() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let creator = FileCreator()
        let first = try creator.create(.json, in: root)
        let second = try creator.create(.json, in: root)

        #expect(first.lastPathComponent == "Untitled.json")
        #expect(second.lastPathComponent == "Untitled 2.json")
        #expect(try String(contentsOf: first, encoding: .utf8) == "{\n  \n}\n")
    }

    @Test
    func rejectsAFileAsDestination() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        #expect(throws: FileCreatorError.self) {
            try FileCreator().create(.text, in: file)
        }
    }

    @Test
    func concurrentCreationNeverOverwrites() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let created = try await withThrowingTaskGroup(of: URL.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    try FileCreator().create(.text, in: root)
                }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }

        #expect(Set(created.map(\.lastPathComponent)).count == 8)
        #expect(created.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test
    func createsFoldersAndClipboardStyleContentsWithoutOverwriting() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let creator = FileCreator()
        let firstFolder = try creator.createDirectory(in: root)
        let secondFolder = try creator.createDirectory(in: root)
        let file = try creator.create(
            contents: Data("clipboard text".utf8),
            preferredFilename: "Untitled.txt",
            in: root
        )

        let folderName = L10n.text(
            "file.untitled_folder",
            fallback: "未命名文件夹"
        )
        #expect(firstFolder.lastPathComponent == folderName)
        #expect(secondFolder.lastPathComponent == "\(folderName) 2")
        #expect(try String(contentsOf: file, encoding: .utf8) == "clipboard text")
        #expect(throws: FileCreatorError.self) {
            try creator.create(
                contents: Data(),
                preferredFilename: "../escape",
                in: root
            )
        }
    }
}
