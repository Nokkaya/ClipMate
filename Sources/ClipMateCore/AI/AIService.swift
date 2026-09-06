import Foundation

/// AI 快速动作（⌘K 浮层）。
public enum AIAction: String, CaseIterable, Identifiable {
    case translate, summarize, rewrite, grammar, explainCode, extract, custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .translate: return "翻译"
        case .summarize: return "摘要"
        case .rewrite: return "润色"
        case .grammar: return "修正语法"
        case .explainCode: return "解释代码"
        case .extract: return "提取要点"
        case .custom: return "自定义"
        }
    }

    public var systemImage: String {
        switch self {
        case .translate: return "globe"
        case .summarize: return "text.alignleft"
        case .rewrite: return "wand.and.stars"
        case .grammar: return "checkmark.circle"
        case .explainCode: return "curlybraces"
        case .extract: return "list.bullet"
        case .custom: return "slider.horizontal.3"
        }
    }

    public func prompt(for content: String, custom: String) -> String {
        let trimmed = String(content.prefix(8000))
        switch self {
        case .translate:
            return "请将下面的内容翻译成简体中文；如果原文已经是中文，则翻译成英文。只输出译文，不要解释：\n\n\(trimmed)"
        case .summarize:
            return "请用不超过 5 个要点总结下面的内容：\n\n\(trimmed)"
        case .rewrite:
            return "请把下面的内容改写得更专业、更通顺，保持原意，只输出结果：\n\n\(trimmed)"
        case .grammar:
            return "请修正下面内容中的拼写和语法错误，保持原意和语言，只输出修正后的结果：\n\n\(trimmed)"
        case .explainCode:
            return "请解释下面代码或命令的作用，简明扼要：\n\n\(trimmed)"
        case .extract:
            return "请从下面的内容中提取关键信息（如联系人、日期、金额、链接等），以列表输出：\n\n\(trimmed)"
        case .custom:
            let instruction = custom.trimmingCharacters(in: .whitespacesAndNewlines)
            return instruction.isEmpty
                ? trimmed
                : "\(instruction)\n\n---\n以下是剪贴板内容：\n\(trimmed)"
        }
    }
}

public enum AIError: LocalizedError {
    case notConfigured
    case requestFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "AI 未配置：请在设置中启用并填写端点与模型"
        case .requestFailed(let detail): return detail
        }
    }
}

public struct AIProviderConfig {
    public var endpoint: URL
    public var model: String
    public var apiKey: String?

    public init(endpoint: URL, model: String, apiKey: String?) {
        self.endpoint = endpoint
        self.model = model
        self.apiKey = apiKey
    }
}

/// OpenAI 兼容 Chat Completions 流式 Provider。
/// 同一协议覆盖：OpenAI / Anthropic 兼容网关 / Ollama（http://localhost:11434/v1）/ LM Studio 等。
public struct OpenAICompatProvider {
    public let config: AIProviderConfig

    public init(config: AIProviderConfig) {
        self.config = config
    }

    public func stream(system: String, user: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: config.endpoint.appendingPathComponent("chat/completions"))
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    if let key = config.apiKey, !key.isEmpty {
                        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                    }
                    let body: [String: Any] = [
                        "model": config.model,
                        "stream": true,
                        "messages": [
                            ["role": "system", "content": system],
                            ["role": "user", "content": user],
                        ],
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        var detail = ""
                        for try await line in bytes.lines {
                            detail += line
                            if detail.count > 400 { break }
                        }
                        throw AIError.requestFailed("HTTP \(http.statusCode)：\(detail)")
                    }
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = object["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let content = delta["content"] as? String, !content.isEmpty else { continue }
                        continuation.yield(content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// AI 门面：读取设置装配 Provider。
public final class AIService {
    private let settings: AppSettings

    public init(settings: AppSettings) {
        self.settings = settings
    }

    public var isConfigured: Bool {
        guard settings.aiEnabled else { return false }
        guard let url = URL(string: settings.aiEndpoint), url.scheme != nil else { return false }
        return !settings.aiModel.isEmpty
    }

    public func stream(prompt: String) -> AsyncThrowingStream<String, Error> {
        guard isConfigured, let url = URL(string: settings.aiEndpoint) else {
            return AsyncThrowingStream { $0.finish(throwing: AIError.notConfigured) }
        }
        let key = settings.aiAPIKey
        let config = AIProviderConfig(endpoint: url, model: settings.aiModel, apiKey: key.isEmpty ? nil : key)
        return OpenAICompatProvider(config: config).stream(
            system: "你是 macOS 剪贴板助手，直接输出结果，不要输出多余的客套解释。",
            user: prompt
        )
    }

    public func testConnection() async -> String {
        guard isConfigured else { return "未配置：请启用 AI 并填写端点与模型" }
        do {
            var result = ""
            for try await delta in stream(prompt: "请只回复：OK") {
                result += delta
                if result.count > 32 { break }
            }
            return result.isEmpty ? "连接成功，但未返回内容" : "连接成功：\(result.prefix(32))"
        } catch {
            return "连接失败：\(error.localizedDescription)"
        }
    }
}
