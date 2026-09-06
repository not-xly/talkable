import SwiftUI
import AVFoundation
import Speech

/// First-run setup: welcome, required permissions, the optional AI polish and
/// the hotkey explanation. Follows the shared design language (XlyTheme).
///
/// Gating: the transcription path (microphone + speech recognition) is
/// required before setup can be completed; the AI polish model is optional.
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

    private var transcriptionReady: Bool { micOk && speechOk }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ForEach(0..<totalSteps, id: \.self) { i in
                    Circle()
                        .fill(i <= step ? XlyTheme.accent : XlyTheme.border)
                        .frame(width: 10, height: 10)
                    if i < totalSteps - 1 {
                        Rectangle()
                            .fill(i < step ? XlyTheme.accent : XlyTheme.border)
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

            VStack(spacing: 8) {
                if step == totalSteps - 1 && !transcriptionReady {
                    Text("Microphone and speech recognition are required before finishing setup.")
                        .font(.caption)
                        .foregroundStyle(XlyTheme.textSecondary)
                }
                HStack {
                    if step > 0 {
                        Button("Back") { step -= 1 }
                            .buttonStyle(GhostButtonStyle())
                    }
                    Spacer()
                    if step < totalSteps - 1 {
                        Button(step == 0 ? "Get started" : "Next") { step += 1 }
                            .buttonStyle(DarkButtonStyle())
                            .keyboardShortcut(.return)
                    } else {
                        Button("Done, let's dictate!") { finish() }
                            .buttonStyle(DarkButtonStyle())
                            .keyboardShortcut(.return)
                            .disabled(!transcriptionReady)
                    }
                }
            }
            .padding(20)
        }
        .frame(width: 540, height: 520)
        .background(XlyTheme.background)
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
            Text("Next: the permissions transcription needs (required), and whether you want local AI to polish the text (optional).")
                .foregroundStyle(XlyTheme.textSecondary)
        }
    }

    // MARK: - Step 1

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Required permissions").font(.title2.bold())
                ChipView(kind: .required)
            }
            Text("Transcription can't run without the first two. Each one has a concrete reason:")
                .font(.callout)
                .foregroundStyle(XlyTheme.textSecondary)

            VStack(alignment: .leading, spacing: 0) {
                permissionRow(
                    "Microphone — to hear you. Audio is processed in memory and discarded.",
                    ok: micOk
                ) {
                    Task {
                        micOk = await SystemPermissions.microphone()
                    }
                }
                Divider().overlay(XlyTheme.border)
                permissionRow(
                    "Speech recognition — the system's on-device transcriber.",
                    ok: speechOk
                ) {
                    Task {
                        speechOk = await SystemPermissions.speechRecognition()
                    }
                }
                Divider().overlay(XlyTheme.border)
                permissionRow(
                    "Input Monitoring — to catch the right ⌘ key system-wide.",
                    ok: appState.hotkeyActive
                ) {
                    openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
                }
                Divider().overlay(XlyTheme.border)
                permissionRow(
                    "Accessibility — to type the text into the app you're using.",
                    ok: AXIsProcessTrusted()
                ) {
                    openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
                }
            }
            .card(padding: 0)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 10) {
                if !appState.hotkeyActive {
                    Button("Grant the key permissions, then retry hotkey") {
                        _ = appState.installHotkeys()
                    }
                    .buttonStyle(GhostButtonStyle())
                    .font(.callout)
                }
                Spacer()
            }
            Text("The last two can also be granted later in Preferences.")
                .font(.caption)
                .foregroundStyle(XlyTheme.textSecondary)
        }
    }

    private func permissionRow(_ text: String, ok: Bool, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(ok ? Color.green : XlyTheme.warnText)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(text).font(.callout)
                if !ok {
                    Button("Grant", action: action)
                        .font(.caption)
                        .buttonStyle(GhostButtonStyle())
                }
            }
            Spacer()
        }
        .padding(12)
    }

    // MARK: - Step 2

    private var ai: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Polish the text with AI?").font(.title2.bold())
                ChipView(kind: .optional)
            }
            Toggle("Polish with local AI", isOn: $aiEnabled)
            Text("Without AI: text is pasted as transcribed (basic punctuation: capital letter and period).\n\nWith AI: a small model running **on your Mac** fixes punctuation, accents, capitals and removes fillers like “uh” or “you know”.")
                .font(.callout)
            if aiEnabled {
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
                            .foregroundStyle(XlyTheme.textSecondary)
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
                        .buttonStyle(GhostButtonStyle())
                        if let aiError {
                            Text("Couldn't download: \(aiError). You can retry later in Preferences.")
                                .font(.caption)
                                .foregroundStyle(XlyTheme.danger)
                        } else {
                            Text("Optional: you can also leave it for later — it downloads itself the first time you dictate with AI on. Setup can finish without it.")
                                .font(.caption)
                                .foregroundStyle(XlyTheme.textSecondary)
                        }
                    }
                }
                .card()
            }
        }
    }

    // MARK: - Step 3

    private var hotkey: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your dictation key").font(.title2.bold())
            HStack(spacing: 12) {
                Image(systemName: appState.hotkeyActive ? "command" : "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(appState.hotkeyActive ? XlyTheme.accent : XlyTheme.warnText)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Right ⌘")
                        .font(XlyTheme.mono.weight(.semibold))
                    Text("the ⌘ key to the right of the space bar")
                        .font(.caption)
                        .foregroundStyle(XlyTheme.textSecondary)
                }
            }
            .card()
            Text("• **Hold** right ⌘, speak, release: the text types itself.\n• **Quick tap**: start dictating; tap again to paste.")
            Text("Tip: try it right now — put your cursor anywhere and hold right ⌘.")
                .foregroundStyle(XlyTheme.textSecondary)
                .font(.callout)
        }
    }

    // MARK: - Helpers

    private func openSettings(_ url: String) {
        if let url = URL(string: url) {
            NSWorkspace.shared.open(url)
        }
    }

    private func finish() {
        guard transcriptionReady else { return }
        settings.polishWithAI = aiEnabled
        UserDefaults.standard.set(true, forKey: "onboardingComplete")
        dismiss()
    }
}
