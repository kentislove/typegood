import Foundation

/// LLM 語意後處理器：使用大型語言模型修正語音辨識結果
struct LLMPostProcessor {

    private let provider: APIProvider
    private let apiKey: String
    private let systemPrompt: String
    private let modelName: String
    private let reasoningEffort: ReasoningEffort

    init(provider: APIProvider,
         apiKey: String,
         systemPrompt: String,
         modelName: String,
         reasoningEffort: ReasoningEffort = .unspecified) {
        self.provider = provider
        self.apiKey = apiKey
        self.systemPrompt = systemPrompt
        self.modelName = modelName
        self.reasoningEffort = reasoningEffort
    }

    /// 使用 LLM 修正辨識文字
    ///
    /// 各家模型支援的參數並不一致（例如指定 reasoning_effort 時不可再送 temperature），
    /// 被拒絕的參數會自動拿掉重送，避免換個模型就讓語意修正整個靜默失效。
    func process(_ text: String) async throws -> String {
        guard !text.isEmpty else { return text }

        var sendReasoning = reasoningEffort != .unspecified
        var sendTemperature = !sendReasoning

        while true {
            do {
                return try await send(text, reasoning: sendReasoning, temperature: sendTemperature)
            } catch LLMError.unsupportedParameter(let name) where name == "reasoning_effort" && sendReasoning {
                sendReasoning = false
                sendTemperature = true
            } catch LLMError.unsupportedParameter(let name) where name == "temperature" && sendTemperature {
                sendTemperature = false
            }
        }
    }

    private func send(_ text: String, reasoning: Bool, temperature: Bool) async throws -> String {
        let url = URL(string: provider.chatCompletionURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        var body: [String: Any] = [
            "model": modelName,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            // gpt-5 以後的模型不接受 max_tokens；max_completion_tokens 新舊模型通用。
            // 額度開大一點，避免推理模型把預算耗在推理上導致回傳空字串。
            "max_completion_tokens": 4096
        ]
        if reasoning {
            body["reasoning_effort"] = reasoningEffort.rawValue
        }
        if temperature {
            body["temperature"] = 0.1
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "未知錯誤"
            if httpResponse.statusCode == 400 {
                if errorMsg.contains("reasoning_effort") {
                    throw LLMError.unsupportedParameter("reasoning_effort")
                }
                if errorMsg.contains("temperature") {
                    throw LLMError.unsupportedParameter("temperature")
                }
            }
            throw LLMError.apiError("HTTP \(httpResponse.statusCode): \(errorMsg)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.invalidResponse
        }

        let result = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? text : result
    }
}

/// LLM 後處理錯誤
enum LLMError: LocalizedError {
    case invalidResponse
    case apiError(String)
    case unsupportedParameter(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "LLM API 回應格式錯誤"
        case .apiError(let msg): return "LLM API 錯誤：\(msg)"
        case .unsupportedParameter(let name): return "模型不支援參數：\(name)"
        }
    }
}
