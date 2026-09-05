import SwiftUI
import AVFoundation
import Speech

/// First-run setup: welcome, permissions, the AI-model decision and the
/// hotkey explanation.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var appState = AppState.shared

    @State private var step = 0
    @State private var micOk = false
    @State private var speechOk = false
    @State private var aiEnabled = false
    @State private var downloadingAI = false
    @State private var aiReady = AIPolisher.isModelLocal
    @State private var aiError: String?

    private let totalSteps = 4

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ForEach(0..<totalSteps, id: \.self) { i in
                    Circle()
                        .fill(i <= step ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 10, height: 10)
                    if i < totalSteps - 1 {
                        Rectangle()
                            .fill(i < step ? Color.accentColor : Color.gray.opacity(0.3))
                            .frame(height: 2)
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 20)

            Group {
                switch step {
                case 0: welcome
                case 1: permissions
                case 2: ai
                default: hotkey
                }
            }
            .padding(28)
            .frame(maxHeight: .infinity, alignment: .top)

            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }
                }
                Spacer()
                if step < totalSteps - 1 {
                    Button(step == 0 ? "Get started" : "Next") { step += 1 }
                        .keyboardShortcut(.return)
                } else {
                    Button("Done, let's dictate!") { finish() }
                        .keyboardShortcut(.return)
                }
            }
            .padding(20)
        }
        .frame(width: 520, height: 480)
        .onAppear {
            micOk = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            speechOk = SFSpeechRecognizer.authorizationStatus() == .authorized
        }
    }

    // MARK: - Step 0

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Hi! I'm Talkable")
                .font(.title2.bold())
            Text("Dictate with the right ⌘ key (hold it, speak, release) and the text gets typed wherever your cursor is, in any app.")
            Text("Everything runs **on your Mac**: neither your audio nor your text ever leaves this computer. No accounts, no cloud, no limits.")
            Text("Before we start I need a couple of permissions (the only thing macOS requires) and we'll decide if you want local AI to polish the text.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Step 1

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Required permissions").font(.title2.bold())
            Text("Each one has a concrete reason:")
                .font(.callout)
                .foregroundStyle(.secondary)

            row("Microphone — to hear you. Audio is processed in memory and discarded.",
                granted: micOk) {
                Task {
                    micOk = await withCheckedContinuation { c in
                        AVCaptureDevice.requestAccess(for: .audio) { c.resume(returning: $0) }
                    }
                }
            }
            row("Speech recognition — the system's on-device transcriber.",
                granted: speechOk) {
                Task {
                    speechOk = await withCheckedContinuation { c in
                        SFSpeechRecognizer.requestAuthorization { st in
                            c.resume(returning: st == .authorized)
                        }
                    }
                }
            }
            row("Input Monitoring — to catch the right ⌘ key system-wide.",
                granted: appState.hotkeyActive) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                    NSWorkspace.shared.open(url)
                }
            }
            row("Accessibility — to type the text into the app you're using.",
                granted: AXIsProcessTrusted()) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }

            if !appState.hotkeyActive {
                Button("Done — retry hotkey") { _ = appState.installHotkeys() }
                    .font(.callout)
            }
            Text("You can skip this step and grant them later in Preferences.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func row(_ text: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(granted ? Color.green : Color.orange)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(text).font(.callout)
                if !granted {
                    Button("Grant", action: action)
                        .font(.caption)
                        .controlSize(.small)
                }
            }
            Spacer()
        }
    }

    // MARK: - Step 2

    private var ai: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Polish the text with AI?").font(.title2.bold())
            Toggle("Polish with local AI (Qwen3)", isOn: $aiEnabled)
            Text("Without AI: text is pasted as transcribed (basic punctuation: capital letter and period).\n\nWith AI: a small model (Qwen3-0.6B) running **on your Mac** fixes punctuation, accents, capitals and removes fillers like “uh” or “you know”.")
                .font(.callout)
            if aiEnabled {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("For that I need to download the model once: **~335 MB**. Afterwards it works offline forever.")
                            .font(.callout)
                        if aiReady {
                            Label("Model downloaded", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else if downloadingAI {
                            ProgressView()
                            Text("Downloading model… (may take a few minutes)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button("Download now (~335 MB)") {
                                downloadingAI = true
                                Task {
                                    do {
                                        try await AIPolisher.prepare()
                                        aiReady = true
                                    } catch {
                                        aiError = error.localizedDescription
                                    }
                                    downloadingAI = false
                                }
                            }
                            if let aiError {
                                Text("Couldn't download: \(aiError). You can retry later in Preferences.")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            } else {
                                Text("Or leave it for later: it downloads itself the first time you dictate with AI on.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(6)
                }
            }
        }
    }

    // MARK: - Step 3

    private var hotkey: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your dictation key").font(.title2.bold())
            GroupBox {
                HStack {
                    Image(systemName: appState.hotkeyActive ? "command" : "exclamationmark.triangle")
                        .font(.title)
                    VStack(alignment: .leading) {
                        Text("Right ⌘").bold()
                        Text("the ⌘ key to the right of the space bar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(6)
            }
            Text("• **Hold** right ⌘, speak, release: the text types itself.\n• **Quick tap**: start dictating; tap again to paste.")
            Text("Tip: try it right now — put your cursor anywhere and hold right ⌘.")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }

    private func finish() {
        settings.polishWithAI = aiEnabled
        UserDefaults.standard.set(true, forKey: "onboardingComplete")
        dismiss()
    }
}
