import Foundation
import Testing
@testable import RightClickCore

struct LocalActionLogTests {
    @Test
    func persistsOnlyTheNewestBoundedRecordsWithPrivatePermissions() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("action-log.json")
        let store = LocalActionLogStore(
            fileURL: url,
            maximumRecordCount: 3
        )

        for index in 0..<5 {
            store.append(LocalActionRecord(
                id: UUID(uuidString: "00000000-0000-4000-8000-00000000000\(index)")!,
                date: Date(timeIntervalSince1970: TimeInterval(index)),
                source: .host,
                action: .copyPath,
                result: .succeeded
            ))
        }

        #expect(store.records().map(\.date) == [
            Date(timeIntervalSince1970: 2),
            Date(timeIntervalSince1970: 3),
            Date(timeIntervalSince1970: 4)
        ])
        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.path
        )
        let permissions = try #require(
            attributes[.posixPermissions] as? NSNumber
        )
        #expect(permissions.intValue & 0o777 == 0o600)
    }

    @Test
    func corruptOrOversizedLogsFailClosedToAnEmptyHistory() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("action-log.json")

        try Data("not-json".utf8).write(to: url)
        #expect(LocalActionLogStore.load(from: url).isEmpty)

        try Data(repeating: 0x41, count: 1_048_577).write(to: url)
        #expect(LocalActionLogStore.load(from: url).isEmpty)
    }

    @Test
    func reportMergesAndLimitsRecordsWithoutAcceptingSensitiveFields() {
        let host = LocalActionRecord(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            date: Date(timeIntervalSince1970: 1),
            source: .host,
            action: .runCodexCLI,
            result: .failed,
            errorCategory: .executionFailed
        )
        let extensionRecord = LocalActionRecord(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
            date: Date(timeIntervalSince1970: 2),
            source: .finderExtension,
            action: .copyPath,
            result: .succeeded
        )

        let report = LocalActionLogReport.make(
            hostRecords: [host],
            extensionRecords: [extensionRecord],
            appVersion: "1.0.0 (10000)",
            generatedAt: Date(timeIntervalSince1970: 3),
            maximumRecordCount: 1
        )

        #expect(report.contains("finder-extension\tcopyPath\tsucceeded\t-"))
        #expect(!report.contains("runCodexCLI\tfailed"))
        #expect(report.contains("no paths, filenames, commands, arguments"))
    }

    @Test
    func sessionMarkerReportsAnUncleanPreviousTermination() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let logURL = directory.appendingPathComponent("action-log.json")
        let markerURL = directory.appendingPathComponent("host-session.active")
        let store = LocalActionLogStore(fileURL: logURL)
        let first = LocalActionSessionTracker(
            store: store,
            markerURL: markerURL
        )
        first.begin(date: Date(timeIntervalSince1970: 1))

        let second = LocalActionSessionTracker(
            store: store,
            markerURL: markerURL
        )
        second.begin(date: Date(timeIntervalSince1970: 2))
        second.end(date: Date(timeIntervalSince1970: 3))

        let records = store.records()
        #expect(records.contains {
            $0.action == .applicationSession
                && $0.result == .failed
                && $0.errorCategory == .unexpectedTermination
        })
        #expect(!FileManager.default.fileExists(atPath: markerURL.path))
    }

    @Test
    func everyPublishedActionMapsToAStableClosedLogName() {
        #expect(
            RightClickAction.allMenuActions.map {
                LocalActionName($0).rawValue
            } == RightClickAction.allMenuActions.map(\.logDescription)
        )
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        return directory
    }
}
