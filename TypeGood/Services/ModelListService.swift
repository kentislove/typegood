import Foundation

/// LLM 推理強度（僅部分模型支援）
///
/// 指定推理強度時不可同時送出 temperature，兩者並存會被 API 拒絕。
/// 模型若不支援此參數，`LLMPostProcessor` 會自動拿掉後重送。
enum ReasoningEffort: String, Codable, CaseIterable, Identifiable {
    case unspecified = "unspecified"   // 不送出 reasoning_effort
    case none = "none"
    case low = "low"
    case medium = "medium"
    case high = "high"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .unspecified: return "不指定（送出 temperature）"
        case .none: return "none — 不推理"
        case .low: return "low — 建議"
        case .medium: return "medium"
        case .high: return "high — 明顯變慢"
        }
    }
}

/// LLM 模型清單服務
enum ModelListService {

    /// OpenAI 推薦模型（依實測整理，適合語音輸入的文字整理用途）
    ///
    /// 實測結論：這個任務不需要高階模型，模型世代比推理強度更重要。
    /// gpt-5.4-nano 在 345 次對抗性測試中失誤 1 次，延遲中位數 0.66s，
    /// 成本約為 gpt-4.1 的 1/9，是速度、成本與穩定度的最佳平衡點。
    static let openAIModels = [
        "gpt-5.4-nano",     // 預設：最快、最便宜的穩定選擇
        "gpt-4.1-mini",     // 備選：實測零失誤，但世代較舊、成本約兩倍
        "gpt-5.4-mini",
        "gpt-5.6-luna",
        "gpt-5.4",
        "gpt-4.1",
        "gpt-5-nano",       // 最便宜，但實測約 4.6% 機率把文字改壞
        "gpt-4o-mini",
    ]

    /// Groq 推薦模型
    static let groqModels = [
        "openai/gpt-oss-20b",
        "openai/gpt-oss-120b",
        "qwen/qwen3.8-27b",
        "groq/compound-mini",
    ]

    /// 取得指定供應商的模型清單
    static func models(for provider: APIProvider) -> [String] {
        switch provider {
        case .openai: return openAIModels
        case .groq: return groqModels
        }
    }
}
