import Speech

final class SpeechTranscriber {
    /// Recognizers are expensive to build; the docs recommend creating one
    /// per locale and reusing it, so they live in a process-wide cache.
    private static let cacheLock = NSLock()
    private static var cache: [String: SFSpeechRecognizer] = [:]

    private static func recognizer(forLocale localeID: String) -> SFSpeechRecognizer? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = cache[localeID] {
            return cached
        }
        let fresh = SFSpeechRecognizer(locale: Locale(identifier: localeID))
        cache[localeID] = fresh
        return fresh
    }

    private var recognizer: SFSpeechRecognizer?
    private let request = SFSpeechAudioBufferRecognitionRequest()
    private var task: SFSpeechRecognitionTask?
    private var completion: ((String, Error?) -> Void)?
    private var lastPartial = ""
    private var finished = false

    func start(
        localeID: String,
        onDeviceOnly: Bool,
        onUpdate: @escaping (String) -> Void,
        onFailure: @escaping (String) -> Void
    ) throws {
        guard let rec = Self.recognizer(forLocale: localeID) else {
            onFailure("The “\(localeID)” language has no speech support.")
            return
        }
        recognizer = rec
        guard rec.isAvailable else {
            onFailure("Speech recognition isn't available right now.")
            return
        }
        if onDeviceOnly && !rec.supportsOnDeviceRecognition {
            onFailure("“\(localeID)” has no on-device model. Pick another language or turn off “On-device only” in Preferences.")
            return
        }
        request.shouldReportPartialResults = true
        if onDeviceOnly {
            request.requiresOnDeviceRecognition = true
        }
        task = rec.recognitionTask(with: request) { [weak self] result, error in
            guard let self, !self.finished else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                if text != self.lastPartial {
                    self.lastPartial = text
                    onUpdate(text)
                }
                if result.isFinal {
                    self.deliver(text, nil)
                }
            }
            if let error {
                // If we already have partial text, deliver it anyway.
                self.deliver(self.lastPartial, self.lastPartial.isEmpty ? error : nil)
            }
        }
    }

    private func deliver(_ text: String, _ error: Error?) {
        guard !finished else { return }
        finished = true
        let cb = completion
        completion = nil
        cb?(text, error)
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        request.append(buffer)
    }

    /// Closes the audio and waits for the final result. If it takes longer
    /// than 8 s, delivers whatever arrived last. Retains itself until then.
    func finish(onDone: @escaping (String, Error?) -> Void) {
        completion = onDone
        request.endAudio()
        task?.finish()
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [self] in
            guard !finished else { return }
            deliver(lastPartial, nil)
            cancel()
        }
    }

    func cancel() {
        finished = true
        task?.cancel()
        task = nil
    }
}
