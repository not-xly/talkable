import AppKit
import AVFoundation
import Speech
import Combine

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    enum Status: Equatable {
        case idle
        case recording
        case transcribing
        case error(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var partialText: String = ""
    @Published private(set) var hotkeyActive = false

    var isDictating: Bool {
        status == .recording || status == .transcribing
    }

    let settings = SettingsStore.shared
    private let audio = AudioCapture()
    private var transcriber: SpeechTranscriber?
    private let typer = TextTyper()
    private let hud = HUDController()
    private var hotkey: HotkeyManager?
    private var recordingStart = Date.distantPast
    private var tapArmsToggle = false

    /// Global key pressed (right ⌘). Hybrid behavior: hold to dictate and
    /// release to paste; a quick tap toggles (tap again to paste).
    func hotkeyPressed() {
        #if DEBUG
        NSLog("Talkable: hotkeyPressed in state \(status)")
        #endif
        switch status {
        case .idle, .error:
            startRecording()
        case .recording:
            if tapArmsToggle { stopAndPaste() }
        case .transcribing:
            break
        }
    }

    func installHotkeys() -> Bool {
        if hotkeyActive { return true }
        let hk = hotkey ?? HotkeyManager(keyCode: SettingsStore.hotkeyKeyCode)
        guard hk.install() else {
            hotkeyActive = false
            return false
        }
        hk.onKeyDown = { [weak self] in self?.hotkeyPressed() }
        hk.onKeyUp = { [weak self] in self?.keyReleased() }
        hotkey = hk
        hotkeyActive = true
        return true
    }

    private func startRecording() {
        cancel()
        status = .recording
        partialText = ""
        recordingStart = Date()
        tapArmsToggle = false
        Task { await prepareAndRecord() }
    }

    private func prepareAndRecord() async {
        // Fast paths: already-granted permissions return immediately instead
        // of paying a system round-trip before every dictation.
        guard await SystemPermissions.microphone() else {
            fail("No microphone access. Grant it in Settings › Privacy & Security › Microphone.")
            return
        }
        guard await SystemPermissions.speechRecognition() else {
            fail("No speech recognition permission. Check Settings › Privacy & Security › Speech Recognition.")
            return
        }

        let t = SpeechTranscriber()
        do {
            try t.start(
                localeID: settings.localeID,
                onDeviceOnly: settings.onDeviceOnly,
                onUpdate: { [weak self] text in
                    Task { @MainActor in
                        guard let self, self.status == .recording else { return }
                        self.partialText = text
                        self.hud.showText(text)
                    }
                },
                onFailure: { [weak self] msg in
                    Task { @MainActor in self?.fail(msg) }
                }
            )
        } catch {
            fail("Couldn't start recognition: \(error.localizedDescription)")
            return
        }
        transcriber = t

        audio.onBuffer = { [weak t] buffer in t?.append(buffer) }
        do {
            try audio.start()
        } catch {
            fail("Couldn't open the microphone: \(error.localizedDescription)")
            return
        }

        if settings.sound { NSSound(named: "Tink")?.play() }
        hud.showRecording()
    }

    private func keyReleased() {
        guard status == .recording else { return }
        if Date().timeIntervalSince(recordingStart) < 0.30 {
            // Quick tap: enter toggle mode, the next press stops and pastes.
            tapArmsToggle = true
            return
        }
        stopAndPaste()
    }

    func stopAndPaste() {
        guard status == .recording else { return }
        status = .transcribing
        audio.stop()
        if settings.sound { NSSound(named: "Pop")?.play() }
        hud.showTranscribing()
        transcriber?.finish { [weak self] text, error in
            Task { @MainActor in
                self?.paste(text: text, error: error)
                self?.transcriber = nil
            }
        }
    }

    private func paste(text: String, error: Error?) {
        guard status == .transcribing else { return }
        if let error {
            fail("Transcription failed: \(error.localizedDescription)")
            return
        }
        let clean = TextProcessor.polish(text, enabled: settings.punctuation)
        guard !clean.isEmpty else {
            status = .idle
            partialText = ""
            hud.hide()
            return
        }

        if settings.polishWithAI {
            hud.showPolishing()
            Task { @MainActor in
                let polished = await AIPolisher.polish(clean)
                self.typeAndClose(polished + " ")
            }
        } else {
            typeAndClose(clean + " ")
        }
    }

    /// Types the final text and returns to the initial state.
    private func typeAndClose(_ text: String) {
        typer.type(text) { ok in
            if !ok {
                self.hud.showError("Paste with ⌘V (grant “Accessibility” for auto-paste)")
            }
        }
        status = .idle
        partialText = ""
        hud.hide()
    }

    func cancel() {
        audio.stop()
        transcriber?.cancel()
        transcriber = nil
        status = .idle
        partialText = ""
        hud.hide()
    }

    private func fail(_ msg: String) {
        audio.stop()
        transcriber?.cancel()
        transcriber = nil
        status = .error(msg)
        hud.showError(msg)
    }
}

enum TextProcessor {
    static func polish(_ text: String, enabled: Bool) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard enabled, !s.isEmpty else { return s }
        s = s.prefix(1).uppercased() + s.dropFirst()
        if let last = s.last, !".!?…".contains(last) {
            s += "."
        }
        return s
    }
}

/// Asks for (or confirms) the permissions transcription needs. Safe to call
/// repeatedly: already-granted permissions return without a system prompt.
enum SystemPermissions {
    static func microphone() async -> Bool {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            return true
        }
        return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            AVCaptureDevice.requestAccess(for: .audio) { c.resume(returning: $0) }
        }
    }

    static func speechRecognition() async -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .authorized {
            return true
        }
        return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
    }
}
