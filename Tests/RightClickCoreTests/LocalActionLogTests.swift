import Foundation
import Testing
@testable import RightClickCore

struct LocalActionLogTests {
    @Test
    func persistsOnlyTheNewestBoundedRecordsWithPrivatePermissions() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let logDirectory = directory.appendingPathComponent(
            "Private",
            isDirectory: true
        )
        let url = logDirectory.appendingPathComponent("action-log.json")
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
        store.flush()

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
        let directoryAttributes = try FileManager.default.attributesOfItem(
            atPath: logDirectory.path
        )
        let directoryPermissions = try #require(
            directoryAttributes[.posixPermissions] as? NSNumber
        )
        #expect(directoryPermissions.intValue & 0o777 == 0o700)
    }

    @Test
    func fiveHundredAppendsPersistOnlyTheNewestTwoHundredInOrder() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("action-log.json")
        let store = LocalActionLogStore(fileURL: url)

        for index in 0..<500 {
            store.append(LocalActionRecord(
                date: Date(timeIntervalSince1970: TimeInterval(index)),
                source: .finderExtension,
                action: .copyPath,
                result: .succeeded
            ))
        }
        store.flush()

        let persisted = LocalActionLogStore.load(from: url)
        #expect(persisted.count == 200)
        #expect(persisted.first?.date == Date(timeIntervalSince1970: 300))
        #expect(persisted.last?.date == Date(timeIntervalSince1970: 499))
    }

    @Test
    func appendsWithinTheDebounceWindowProduceOneWrite() async {
        let recorder = PersistenceRecorder()
        let store = LocalActionLogStore(
            fileURL: URL(fileURLWithPath: "/unused/action-log.json"),
            persistenceDelay: .milliseconds(30),
            flushThreshold: 100,
            write: { records, _, _ in try recorder.record(records) }
        )

        for index in 0..<5 {
            store.append(LocalActionRecord(
                date: Date(timeIntervalSince1970: TimeInterval(index)),
                source: .host,
                action: .copyPath,
                result: .succeeded
            ))
        }
        try? await Task.sleep(for: .milliseconds(100))

        #expect(recorder.writeCount == 1)
        #expect(recorder.lastRecordCount == 5)
    }

    @Test
    func explicitFlushIsImmediateAndWriteFailureKeepsBufferedRecords() {
        let recorder = PersistenceRecorder(shouldFail: true)
        let store = LocalActionLogStore(
            fileURL: URL(fileURLWithPath: "/unused/action-log.json"),
            persistenceDelay: .seconds(60),
            flushThreshold: 100,
            write: { records, _, _ in try recorder.record(records) }
        )
        let record = LocalActionRecord(
            source: .host,
            action: .copyPath,
            result: .succeeded
        )

        store.append(record)
        store.flush()

        #expect(recorder.writeCount == 1)
        #expect(store.records() == [record])
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
    func reportOrdersTiedLifecycleRecordsAndAlwaysKeepsOneRecord() throws {
        let date = Date(timeIntervalSince1970: 1)
        let succeeded = LocalActionRecord(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            date: date,
            source: .host,
            action: .applicationSession,
            result: .succeeded
        )
        let started = LocalActionRecord(
            id: UUID(uuidString: "ffffffff-ffff-4fff-8fff-ffffffffffff")!,
            date: date,
            source: .host,
            action: .applicationSession,
            result: .started
        )

        let ordered = LocalActionLogReport.make(
            hostRecords: [succeeded, started],
            extensionRecords: [],
            appVersion: "test",
            generatedAt: date,
            maximumRecordCount: 2
        )
        let startedRange = try #require(ordered.range(of: "\tstarted\t"))
        let succeededRange = try #require(ordered.range(of: "\tsucceeded\t"))
        #expect(startedRange.lowerBound < succeededRange.lowerBound)

        let clamped = LocalActionLogReport.make(
            hostRecords: [started, succeeded],
            extensionRecords: [],
            appVersion: "test",
            generatedAt: date,
            maximumRecordCount: 0
        )
        #expect(!clamped.contains("\tstarted\t"))
        #expect(clamped.contains("\tsucceeded\t"))
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
    func normalSessionLifecycleIsIdempotentAndUsesPrivateMarker() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let markerURL = directory.appendingPathComponent("host-session.active")
        let store = LocalActionLogStore(
            fileURL: directory.appendingPathComponent("action-log.json")
        )
        let tracker = LocalActionSessionTracker(
            store: store,
            markerURL: markerURL
        )
        let start = Date(timeIntervalSince1970: 1)
        let end = Date(timeIntervalSince1970: 2)

        tracker.begin(date: start)
        tracker.begin(date: Date(timeIntervalSince1970: 99))
        #expect(FileManager.default.fileExists(atPath: markerURL.path))
        let markerMode = try #require(
            FileManager.default.attributesOfItem(atPath: markerURL.path)[
                .posixPermissions
            ] as? NSNumber
        ).intValue
        #expect(markerMode == 0o600)

        tracker.end(date: end)
        tracker.end(date: Date(timeIntervalSince1970: 100))

        #expect(store.records().map(\.date) == [start, end])
        #expect(store.records().map(\.result) == [.started, .succeeded])
        #expect(!FileManager.default.fileExists(atPath: markerURL.path))
    }

    @Test
    func logFileLocationsStayInsideTheirExpectedContainers() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let host = LocalActionLogFile.hostURL(homeDirectory: home)
        let extensionHost = LocalActionLogFile.extensionHostURL(
            homeDirectory: home
        )

        #expect(
            host.path
                == "/Users/tester/Library/Application Support/RightClick/action-log.json"
        )
        #expect(
            extensionHost.path
                == "/Users/tester/Library/Containers/com.hheelo.RightClick.FinderExtension/Data/Library/Application Support/RightClick/action-log.json"
        )
        #expect(
            LocalActionLogFile.sessionMarkerURL(for: host).path
                == "/Users/tester/Library/Application Support/RightClick/host-session.active"
        )
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

private final class PersistenceRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let shouldFail: Bool
    private var recordedWriteCount = 0
    private var recordedLastRecordCount = 0

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    var writeCount: Int { lock.withLock { recordedWriteCount } }
    var lastRecordCount: Int { lock.withLock { recordedLastRecordCount } }

    func record(_ records: [LocalActionRecord]) throws {
        lock.withLock {
            recordedWriteCount += 1
            recordedLastRecordCount = records.count
        }
        if shouldFail { throw CocoaError(.fileWriteUnknown) }
    }
}
