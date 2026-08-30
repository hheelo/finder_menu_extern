import Foundation
import Testing
@testable import RightClickCore

struct FileCreatorTests {
    @Test
    func everyBuiltInTemplateHasAStableFilenameAndValidInitialContents() {
        #expect(FileTemplate.allCases.map(\.preferredFilename) == [
            "Untitled.txt",
            "Untitled.md",
            "Untitled.py",
            "Untitled.sh",
            "Untitled.html",
            "Untitled.json",
            "Untitled.csv"
        ])
        #expect(FileTemplate.allCases.allSatisfy { !$0.title.isEmpty })
        #expect(FileTemplate.text.initialContents.isEmpty)
        #expect(FileTemplate.markdown.initialContents.isEmpty)
        #expect(FileTemplate.csv.initialContents.isEmpty)
        #expect(FileTemplate.python.initialContents.hasPrefix("#!/usr/bin/env python3"))
        #expect(FileTemplate.shell.initialContents.hasPrefix("#!/bin/zsh"))
        #expect(FileTemplate.html.initialContents.contains("<!doctype html>"))
        #expect(FileTemplate.html.initialContents.contains("<html lang=\""))
        #expect(FileTemplate.json.initialContents == "{\n  \n}\n")
    }

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
    func appliesTemplateFilenameAndEncodingOverrides() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let creator = FileCreator()
        let bomFile = try creator.create(
            .json,
            override: TemplateOverride(
                filename: "package.json",
                encoding: TemplateEncoding.utf8BOM.rawValue
            ),
            in: root
        )
        let utf16File = try creator.create(
            .python,
            override: TemplateOverride(
                filename: "main.py",
                encoding: TemplateEncoding.utf16.rawValue
            ),
            in: root
        )

        #expect(bomFile.lastPathComponent == "package.json")
        #expect(try Data(contentsOf: bomFile).starts(with: [0xEF, 0xBB, 0xBF]))
        #expect(utf16File.lastPathComponent == "main.py")
        #expect(
            try String(contentsOf: utf16File, encoding: .unicode)
                == FileTemplate.python.initialContents
        )
    }

    @Test
    func invalidTemplateFilenameFallsBackToBuiltInDefault() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let created = try FileCreator().create(
            .markdown,
            override: TemplateOverride(
                filename: "../escape.md",
                encoding: "future-encoding"
            ),
            in: root
        )

        #expect(created.lastPathComponent == "Untitled.md")
        #expect(try Data(contentsOf: created).isEmpty)
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

    @Test
    func validatesFilenameUnitLimitAndKeepsDuplicateNamesWithinIt() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(FileCreator.isSafeFilename(
            String(repeating: "😀", count: 127) + "a"
        ))
        #expect(!FileCreator.isSafeFilename(
            String(repeating: "😀", count: 128)
        ))

        let maximumLengthName = String(repeating: "a", count: 251) + ".txt"
        let creator = FileCreator()
        let first = try creator.create(
            contents: Data(),
            preferredFilename: maximumLengthName,
            in: root
        )
        let second = try creator.create(
            contents: Data(),
            preferredFilename: maximumLengthName,
            in: root
        )

        #expect(first.lastPathComponent.utf16.count == 255)
        #expect(second.lastPathComponent.utf16.count <= 255)
        #expect(second.lastPathComponent.hasSuffix(" 2.txt"))
    }
}
