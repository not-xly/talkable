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

    /// Guards the two statics below: `prepare()` can run from a detached task
    /// while a dictation also needs the model.
    private static let stateLock = NSLock()
    private static var session: ChatSession?
    /// The single in-flight load, shared by every caller so the model is never
    /// loaded (or downloaded) twice in parallel.
    private static var loading: Task<ChatSession, Error>?

    /// Whether the model is already downloaded on this Mac.
    static var isModelLocal: Bool {
        stateLock.withLock { session != nil }
            || UserDefaults.standard.bool(forKey: "aiModelDownloaded")
    }

    /// Loads (and downloads if needed) the model. Cached for reuse.
    static func prepare() async throws {
        if stateLock.withLock({ session != nil }) { return }
        let task = stateLock.withLock { () -> Task<ChatSession, Error> in
            if let loading { return loading }
            let created = Task { () throws -> ChatSession in
                let container = try await #huggingFaceLoadModelContainer(configuration: model)
                return ChatSession(
                    container,
                    instructions: instructions,
                    generateParameters: GenerateParameters(temperature: 0)
                )
            }
            loading = created
            return created
        }
        do {
            let loaded = try await task.value
            stateLock.withLock { session = loaded }
            UserDefaults.standard.set(true, forKey: "aiModelDownloaded")
        } catch {
            // Let a later call retry instead of reusing the failed load.
            stateLock.withLock { loading = nil }
            throw error
        }
    }

    /// Returns the polished text; on any problem, the raw text.
    static func polish(_ raw: String) async -> String {
        do {
            // The reply is about as long as the input, so cap it near that.
            let reply = try await respond(to: raw, maxTokens: raw.count + raw.count / 2 + 32)
            return sane(reply ?? raw, fallback: raw) ?? raw
        } catch {
            return raw
        }
    }

    /// Translates text offline with the same local model.
    /// Requires the model to be installed; otherwise returns the input.
    static func translate(_ text: String, to target: String) async -> String {
        let capped = String(text.suffix(4000))
        do {
            let req = "Translate the following text to \(target). Reply with ONLY the translation, no explanations or quotes. /no_think\n\n\(capped)"
            guard let reply = try await respond(to: req, maxTokens: capped.count * 2 + 64) else {
                return text
            }
            return sane(reply, fallback: text) ?? text
        } catch {
            return text
        }
    }

    /// Runs one independent request. The session keeps its history between
    /// calls, so it is cleared first: a dictation must not see earlier ones.
    /// Returns nil when the model isn't available.
    private static func respond(to input: String, maxTokens: Int) async throws -> String? {
        try await prepare()
        guard let session = stateLock.withLock({ session }) else { return nil }
        await session.clear()
        session.generateParameters.maxTokens = maxTokens
        return try await session.respond(to: input)
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
