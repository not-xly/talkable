import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

/// Polishes the raw transcript with Qwen3-0.6B running locally on the GPU
/// via MLX. The model downloads once from Hugging Face
/// (mlx-community/Qwen3-0.6B-4bit) and works offline after that.
enum AIPolisher {
    static let model = LLMRegistry.qwen3_0_6b_4bit

    static let instructions = """
    You are a voice-dictation proofreader. Only fix the user's text: \
    punctuation, capitalization, accents and filler words, keeping the original \
    language. Don't change the meaning or add content. Reply with ONLY the \
    corrected text, no explanations or quotes. /no_think
    """

    private static var session: ChatSession?

    /// Whether the model is already downloaded on this Mac.
    static var isModelLocal: Bool {
        session != nil || UserDefaults.standard.bool(forKey: "aiModelDownloaded")
    }

    /// Loads (and downloads if needed) the model. Cached for reuse.
    static func prepare() async throws {
        if session == nil {
            let container = try await #huggingFaceLoadModelContainer(
                configuration: model
            )
            session = ChatSession(
                container,
                instructions: instructions,
                generateParameters: GenerateParameters(temperature: 0)
            )
            UserDefaults.standard.set(true, forKey: "aiModelDownloaded")
        }
    }

    /// Returns the polished text; on any problem, the raw text.
    static func polish(_ raw: String) async -> String {
        do {
            try await prepare()
            let reply = try await session?.respond(to: raw) ?? raw
            return sane(reply, fallback: raw) ?? raw
        } catch {
            return raw
        }
    }

    /// Sanity check: if the output drifts too far from the input length,
    /// prefer the raw text.
    private static func sane(_ polished: String, fallback raw: String) -> String? {
        let p = polished.trimmingCharacters(in: .whitespacesAndNewlines)
        let r = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty, !r.isEmpty else { return nil }
        let pr = Double(p.count)
        let rr = Double(r.count)
        guard pr >= rr * 0.4, pr <= rr * 2.5 else { return nil }
        return p
    }
}
