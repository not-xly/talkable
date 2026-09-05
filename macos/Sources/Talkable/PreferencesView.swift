import SwiftUI
import AVFoundation
import Speech

struct PreferencesView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var appState = AppState.shared
    @State private var refresh = false
    private static let ticker = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Talkable") {
                Picker("Language", selection: $settings.localeID) {
                    ForEach(SettingsStore.languages, id: \.id) { language in
                        Text(language.name).tag(language.id)
                    }
                }
                Toggle("On-device only (private and offline)", isOn: $settings.onDeviceOnly)
                Toggle("Automatic basic punctuation", isOn: $settings.punctuation)
                Toggle("Polish with local AI (Qwen3)", isOn: $settings.polishWithAI)
                if settings.polishWithAI {
                    Text("Fixes punctuation, accents and filler words with Qwen3-0.6B running on your Mac. Downloads the model once (~335 MB), then works offline.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Sound on start and stop", isOn: $settings.sound)
            }

            Section("Hotkey") {
                HStack {
                    Image(systemName: appState.hotkeyActive ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(appState.hotkeyActive ? Color.green : Color.orange)
                    Text("Right ⌘ key (global)")
                    Spacer()
                    Text(appState.hotkeyActive ? "Active" : "Missing permission")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                if !appState.hotkeyActive {
                    HStack {
                        Button("Open Settings › Input Monitoring") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        Button("Retry hotkey") {
                            _ = appState.installHotkeys()
                        }
                    }
                }
            }

            Section("How to use") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Hold right ⌘: dictate, release to paste the text.")
                    Text("Quick tap on right ⌘: start; tap again to paste.")
                    Text("Text is typed wherever your cursor is, in any app.")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }

            Section("Permissions") {
                permissionRow("Microphone", ok: micOK())
                permissionRow("Speech recognition", ok: speechOK())
                permissionRow("Accessibility (for auto-paste)", ok: AXIsProcessTrusted())
                if !AXIsProcessTrusted() {
                    Button("Open Settings › Privacy › Accessibility") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                if !micOK() || !speechOK() {
                    Text("Permissions are requested automatically the first time you dictate.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Text("Note: if the app is rebuilt, macOS may ask for permissions again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { refresh.toggle() }
        .onReceive(Self.ticker) { _ in
            refresh.toggle()
        }
    }

    @ViewBuilder
    private func permissionRow(_ name: String, ok: Bool) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(ok ? Color.green : Color.orange)
            Text(name)
            Spacer()
            Text(ok ? "Granted" : "Missing")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    private func micOK() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    private func speechOK() -> Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }
}
