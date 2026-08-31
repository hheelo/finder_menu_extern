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
        let firstResult = try synchronizer.synchronize(
            existing: [],
            sourceDirectory: source,
            mirrorDirectory: mirror
        )
        let first = firstResult.templates
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
        let firstResult = try synchronizer.synchronize(
            existing: [],
            sourceDirectory: source,
            mirrorDirectory: mirror
        )
        let first = firstResult.templates
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
        let secondResult = try synchronizer.synchronize(
            existing: first,
            sourceDirectory: source,
            mirrorDirectory: mirror
        )
        let second = secondResult.templates
        #expect(second.count == 1)
        #expect(second[0].filename == "View.html")
        #expect(second[0].menuSlot == template.menuSlot)
        #expect(
            !FileManager.default.fileExists(
                atPath: mirror.appendingPathComponent("Component.swift").path
            )
        )
    }

    @Test
    func oversizedTemplateDoesNotBlockValidUpdatesOrStaleCleanup() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let mirror = root.appendingPathComponent("mirror", isDirectory: true)
        try FileManager.default.createDirectory(
            at: source,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let synchronizer = TemplateMirror()
        try Data("stale".utf8).write(
            to: source.appendingPathComponent("Stale.txt")
        )
        let initial = try synchronizer.synchronize(
            existing: [],
            sourceDirectory: source,
            mirrorDirectory: mirror
        ).templates

        try FileManager.default.removeItem(
            at: source.appendingPathComponent("Stale.txt")
        )
        try Data(count: TemplateMirror.maximumFileSize + 1).write(
            to: source.appendingPathComponent("Oversized.bin")
        )
        try Data("valid".utf8).write(
            to: source.appendingPathComponent("Valid.txt")
        )

        let result = try synchronizer.synchronize(
            existing: initial,
            sourceDirectory: source,
            mirrorDirectory: mirror
        )

        #expect(result.templates.map(\.filename) == ["Valid.txt"])
        #expect(result.skippedOversizedFilenames == ["Oversized.bin"])
        #expect(FileManager.default.fileExists(
            atPath: mirror.appendingPathComponent("Valid.txt").path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: mirror.appendingPathComponent("Stale.txt").path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: mirror.appendingPathComponent("Oversized.bin").path
        ))
    }

    @Test
    func replacementSymlinkIsNotFollowed() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let mirror = root.appendingPathComponent("mirror", isDirectory: true)
        try FileManager.default.createDirectory(
            at: source,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceFile = source.appendingPathComponent("Note.txt")
        let secretFile = root.appendingPathComponent("Secret.txt")
        try Data("placeholder".utf8).write(to: sourceFile)
        try Data("must not be mirrored".utf8).write(to: secretFile)

        let synchronizer = TemplateMirror { url in
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.createSymbolicLink(
                at: url,
                withDestinationURL: secretFile
            )
        }
        let result = try synchronizer.synchronize(
            existing: [],
            sourceDirectory: source,
            mirrorDirectory: mirror
        )

        #expect(result.templates.isEmpty)
        #expect(!FileManager.default.fileExists(
            atPath: mirror.appendingPathComponent("Note.txt").path
        ))
    }

    @Test
    func growthAfterEnumerationIsStillRejectedAsOversized() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let mirror = root.appendingPathComponent("mirror", isDirectory: true)
        try FileManager.default.createDirectory(
            at: source,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceFile = source.appendingPathComponent("Growing.bin")
        try Data("small".utf8).write(to: sourceFile)

        let synchronizer = TemplateMirror { url in
            try? Data(count: TemplateMirror.maximumFileSize + 1).write(to: url)
        }
        let result = try synchronizer.synchronize(
            existing: [],
            sourceDirectory: source,
            mirrorDirectory: mirror
        )

        #expect(result.templates.isEmpty)
        #expect(result.skippedOversizedFilenames == ["Growing.bin"])
    }

    @Test
    func menuReadUsesTheSameBoundedNoFollowDescriptor() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Template.txt")
        let replacement = root.appendingPathComponent("Replacement.txt")
        try Data("template".utf8).write(to: source)
        try Data("must not be read".utf8).write(to: replacement)

        let reader = TemplateMirror { url in
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.createSymbolicLink(
                at: url,
                withDestinationURL: replacement
            )
        }

        #expect(try reader.loadContents(ofTemplateAt: source) == nil)
    }

    @Test
    func invalidMirrorNodeIsReplacedInsteadOfBlockingSynchronization() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let mirror = root.appendingPathComponent("mirror", isDirectory: true)
        try FileManager.default.createDirectory(
            at: source,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: mirror,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceFile = source.appendingPathComponent("Note.txt")
        let invalidMirror = mirror.appendingPathComponent("Note.txt")
        try Data("fresh".utf8).write(to: sourceFile)
        try FileManager.default.createDirectory(
            at: invalidMirror,
            withIntermediateDirectories: false
        )

        let result = try TemplateMirror().synchronize(
            existing: [],
            sourceDirectory: source,
            mirrorDirectory: mirror
        )

        #expect(result.templates.map(\.filename) == ["Note.txt"])
        #expect(
            try String(contentsOf: invalidMirror, encoding: .utf8) == "fresh"
        )
    }

    @Test
    func newTemplatesUseLowestAvailableSlotsWhileExistingSlotsStayStable() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let mirror = root.appendingPathComponent("mirror", isDirectory: true)
        try FileManager.default.createDirectory(
            at: source,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        for filename in ["A.txt", "B.txt", "C.txt"] {
            try Data(filename.utf8).write(
                to: source.appendingPathComponent(filename)
            )
        }
        let existing = CustomFileTemplate(
            id: "existing",
            title: "B",
            filename: "B.txt",
            menuSlot: 2
        )

        let templates = try TemplateMirror().synchronize(
            existing: [existing],
            sourceDirectory: source,
            mirrorDirectory: mirror
        ).templates

        #expect(templates.map(\.filename) == ["A.txt", "B.txt", "C.txt"])
        #expect(templates.map(\.menuSlot) == [1, 2, 3])
        #expect(templates[1] == existing)
    }
}
