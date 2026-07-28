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
}
