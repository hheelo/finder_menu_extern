import Foundation
import Testing
@testable import RightClickCore

struct TemplateMirrorTests {
    @Test
    func unchangedTemplatesAreNotRewrittenButChangedSourcesAreUpdated() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let mirror = root.appendingPathComponent("mirror", isDirectory: true)
        try FileManager.default.createDirectory(
            at: source,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceFile = source.appendingPathComponent("Note.md")
        let mirroredFile = mirror.appendingPathComponent("Note.md")
        try Data("first".utf8).write(to: sourceFile)

        let synchronizer = TemplateMirror()
        let first = try synchronizer.synchronize(
            existing: [],
            sourceDirectory: source,
            mirrorDirectory: mirror
        )
        let firstInode = try #require(
            FileManager.default.attributesOfItem(atPath: mirroredFile.path)[
                .systemFileNumber
            ] as? NSNumber
        )

        _ = try synchronizer.synchronize(
            existing: first,
            sourceDirectory: source,
            mirrorDirectory: mirror
        )
        let secondInode = try #require(
            FileManager.default.attributesOfItem(atPath: mirroredFile.path)[
                .systemFileNumber
            ] as? NSNumber
        )
        #expect(firstInode == secondInode)

        try Data("second version".utf8).write(to: sourceFile)
        _ = try synchronizer.synchronize(
            existing: first,
            sourceDirectory: source,
            mirrorDirectory: mirror
        )
        #expect(
            try String(contentsOf: mirroredFile, encoding: .utf8)
                == "second version"
        )
    }

    @Test
    func mirrorsRegularFilesKeepsStableSlotsAndRemovesStaleCopies() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let mirror = root.appendingPathComponent("mirror", isDirectory: true)
        try FileManager.default.createDirectory(
            at: source,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("first".utf8).write(
            to: source.appendingPathComponent("Component.swift")
        )
        let nested = source.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(
            at: nested,
            withIntermediateDirectories: false
        )
        try FileManager.default.createSymbolicLink(
            at: source.appendingPathComponent("link.txt"),
            withDestinationURL: source.appendingPathComponent("Component.swift")
        )

        let synchronizer = TemplateMirror()
        let first = try synchronizer.synchronize(
            existing: [],
            sourceDirectory: source,
            mirrorDirectory: mirror
        )
        let template = try #require(first.first)
        #expect(first.count == 1)
        #expect(template.filename == "Component.swift")
        #expect(
            try String(
                contentsOf: mirror.appendingPathComponent("Component.swift"),
                encoding: .utf8
            ) == "first"
        )

        try FileManager.default.removeItem(
            at: source.appendingPathComponent("Component.swift")
        )
        try Data("second".utf8).write(
            to: source.appendingPathComponent("View.html")
        )
        let second = try synchronizer.synchronize(
            existing: first,
            sourceDirectory: source,
            mirrorDirectory: mirror
        )
        #expect(second.count == 1)
        #expect(second[0].filename == "View.html")
        #expect(second[0].menuSlot == template.menuSlot)
        #expect(
            !FileManager.default.fileExists(
                atPath: mirror.appendingPathComponent("Component.swift").path
            )
        )
    }
}
