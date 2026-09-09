import Foundation

/// 线程安全布尔标记（NSLock 保护）。
private final class AtomicBool {
    private let lock = NSLock()
    private var value: Bool
    init(_ initial: Bool = false) { self.value = initial }
    var isSet: Bool {
        lock.lock(); defer { lock.unlock() }
        return value
    }
    func set() {
        lock.lock(); value = true; lock.unlock()
    }
    func getAndSet(_ newValue: Bool) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let old = value
        value = newValue
        return old
    }
}

private final class PipeBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func set(_ newData: Data) {
        lock.lock(); defer { lock.unlock() }
        data = newData
    }
    var current: Data {
        lock.lock(); defer { lock.unlock() }
        return data
    }
}

/// 自定义脚本执行：文本经 stdin 传入 `/bin/sh -c <command>`，stdout 作为结果。
/// 脚本由用户自行配置并以当前用户权限运行，超时 10 秒自动终止。
public enum ScriptRunner {
    public static let timeout: TimeInterval = 10

    public static func run(_ script: ScriptAction, input text: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            switch script.type {
            case .shortcut:
                process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
                process.arguments = ["run", script.command]
            case .shell:
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = ["-c", script.command]
            }

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

            let timedOut = AtomicBool(false)
            let hasResumed = AtomicBool(false)

            // 优化：实时并发消费 stdout 与 stderr。
            // 管道缓冲区一般仅 64KB，若子进程输出超限且父进程未同步读取，子进程将阻塞写死锁，永不退出。
            let group = DispatchGroup()
            let outputBuffer = PipeBuffer()
            let errorBuffer = PipeBuffer()

            group.enter()
            DispatchQueue.global(qos: .utility).async {
                outputBuffer.set(stdout.fileHandleForReading.readDataToEndOfFile())
                group.leave()
            }

            group.enter()
            DispatchQueue.global(qos: .utility).async {
                errorBuffer.set(stderr.fileHandleForReading.readDataToEndOfFile())
                group.leave()
            }

            let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler {
                if process.isRunning {
                    timedOut.set()
                    process.terminate()
                    try? stdout.fileHandleForReading.close()
                    try? stderr.fileHandleForReading.close()
                }
            }
            timer.resume()

            process.terminationHandler = { [weak timer] _ in
                timer?.cancel()
                group.notify(queue: .global(qos: .utility)) {
                    guard !hasResumed.getAndSet(true) else { return }
                    if timedOut.isSet {
                        continuation.resume(throwing: ScriptError.timedOut)
                        return
                    }
                    let outputData = outputBuffer.current
                    let errorData = errorBuffer.current
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
