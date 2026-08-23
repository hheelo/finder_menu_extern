import Darwin
import Foundation
import RightClickCore
import Testing

struct ProcessRunnerTests {
    @Test
    func capturesSuccessfulOutput() async throws {
        let result = try await ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["rightclick"]
        )

        #expect(result.terminationStatus == 0)
        #expect(result.standardOutput == "rightclick\n")
        #expect(result.standardError.isEmpty)
    }

    @Test
    func terminatesProcessAtTimeout() async {
        do {
            _ = try await ProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["10"],
                timeout: 0.1
            )
            Issue.record("进程本应超时")
        } catch let error as ProcessRunnerError {
            guard case let .timedOut(seconds) = error else {
                Issue.record("错误类型不是 timedOut：\(error)")
                return
            }
            #expect(seconds == 0.1)
        } catch {
            Issue.record("返回了错误的异常类型：\(error)")
        }
    }

    @Test
    func terminatesProcessWhenOutputExceedsLimit() async {
        do {
            _ = try await ProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/yes"),
                arguments: [],
                timeout: 2,
                maximumOutputBytes: 1_024
            )
            Issue.record("进程本应因输出超限而终止")
        } catch let error as ProcessRunnerError {
            guard case let .outputLimitExceeded(bytes) = error else {
                Issue.record("错误类型不是 outputLimitExceeded：\(error)")
                return
            }
            #expect(bytes == 1_024)
        } catch {
            Issue.record("返回了错误的异常类型：\(error)")
        }
    }

    @Test
    func cancellationTerminatesTheProcess() async {
        let task = Task {
            try await ProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["2"]
            )
        }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("取消后进程仍然执行到了成功退出")
        } catch is CancellationError {
            // 预期：取消必须传递到独立的进程执行任务。
        } catch {
            Issue.record("返回了错误的异常类型：\(error)")
        }
    }

    @Test
    func timeoutTerminatesDescendantProcesses() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidFile = directory.appendingPathComponent("child.pid")
        let script = """
        sleep 10 &
        child=$!
        printf '%s' "$child" > \(ShellCommandBuilder.quote(pidFile.path))
        wait
        """

        do {
            _ = try await ProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", script],
                timeout: 0.2
            )
            Issue.record("进程树本应超时")
        } catch is ProcessRunnerError {
            // 预期：超时路径应终止 shell 和它启动的 sleep。
        }

        let childPID = try #require(
            Int32(String(contentsOf: pidFile, encoding: .utf8))
        )
        defer {
            if Darwin.kill(childPID, 0) == 0 {
                _ = Darwin.kill(childPID, SIGKILL)
            }
        }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(Darwin.kill(childPID, 0) == -1)
        #expect(errno == ESRCH)
    }

    @Test
    func forceTerminationWaitHasAnUpperBound() async {
        let startedAt = ContinuousClock.now
        let stopped = await ProcessRunner.waitUntilStopped(
            deadline: Date().addingTimeInterval(0.03),
            isRunning: { true }
        )

        #expect(!stopped)
        #expect(startedAt.duration(to: .now) < .milliseconds(200))
    }
}
