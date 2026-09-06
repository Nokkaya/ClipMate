import Foundation

/// 线程安全的超时标记（定时器线程置位、结束线程读取）。
private final class TimeoutFlag {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool {
        lock.lock(); defer { lock.unlock() }
        return value
    }
    func set() {
        lock.lock(); value = true; lock.unlock()
    }
}

/// 自定义脚本执行：文本经 stdin 传入 `/bin/sh -c <command>`，stdout 作为结果。
/// 脚本由用户自行配置并以当前用户权限运行，超时 10 秒自动终止。
public enum ScriptRunner {
    public static let timeout: TimeInterval = 10

    public static func run(_ script: ScriptAction, input text: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", script.command]

            let stdin = Pipe()
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = stderr

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            // 输入超过 64KB 时写入端会阻塞，放后台写并关闭
            let inputData = Data(text.utf8)
            DispatchQueue.global(qos: .utility).async {
                try? stdin.fileHandleForWriting.write(contentsOf: inputData)
                try? stdin.fileHandleForWriting.close()
            }

            let timedOut = TimeoutFlag()
            let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler {
                if process.isRunning {
                    timedOut.set()
                    process.terminate()
                }
            }
            timer.resume()

            process.terminationHandler = { [weak timer] _ in
                timer?.cancel()
                let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
                if timedOut.isSet {
                    continuation.resume(throwing: ScriptError.timedOut)
                    return
                }
                if process.terminationStatus != 0, outputData.isEmpty {
                    let message = String(data: errorData, encoding: .utf8) ?? "脚本执行失败（退出码 \(process.terminationStatus)）"
                    continuation.resume(throwing: ScriptError.failed(message))
                    return
                }
                let output = String(data: outputData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if output.isEmpty {
                    continuation.resume(throwing: ScriptError.failed(
                        String(data: errorData, encoding: .utf8) ?? "脚本无输出"
                    ))
                } else {
                    continuation.resume(returning: String(output.prefix(20000)))
                }
            }
        }
    }

    public enum ScriptError: LocalizedError {
        case timedOut
        case failed(String)

        public var errorDescription: String? {
            switch self {
            case .timedOut: return "脚本执行超时（\(Int(ScriptRunner.timeout))s）"
            case .failed(let message): return message
            }
        }
    }
}
