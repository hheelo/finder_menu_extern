import Foundation
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
}
