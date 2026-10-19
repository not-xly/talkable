import SwiftUI
import AVFoundation
import Speech

struct PreferencesView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var appState = AppState.shared
    // Refreshed when the app becomes active again (user returns from Settings).
    @State private var refreshTick = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section("Talkable") {
                    pickerRow("Language") {
                        Picker("Language", selection: $settings.localeID) {
                            ForEach(SettingsStore.languages, id: \.id) { language in
                                Text(language.name).tag(language.id)
                            }
                        }
                    }
                    pickerRow("Microphone") {
                        Picker("Microphone", selection: $settings.microphoneID) {
                            ForEach(AudioDeviceList.listMicrophones()) { mic in
                                Text(mic.name).tag(mic.id)
                            }
                        }
                    }
                    .help("System default follows macOS Settings › Sound › Input.")
                    Divider()
                    switchRow("On-device only (private and offline)", isOn: $settings.onDeviceOnly)
                    switchRow("Automatic basic punctuation", isOn: $settings.punctuation)
                    switchRow("Polish with local AI (Qwen3)", isOn: $settings.polishWithAI)
                    if settings.polishWithAI {
                        Text("Fixes punctuation, accents and filler words with Qwen3-0.6B running on your Mac. Downloads the model once (~335 MB), then works offline.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    switchRow("Translate offline", isOn: $settings.translateEnabled)
                        .disabled(!AIPolisher.isModelLocal)
                    if settings.translateEnabled || !AIPolisher.isModelLocal {
                        pickerRow("Translate to") {
                            Picker("Translate to", selection: $settings.translateTarget) {
                                Text("English").tag("en")
                                Text("Spanish").tag("es")
                                Text("French").tag("fr")
                                Text("Portuguese").tag("pt")
                                Text("Italian").tag("it")
                                Text("German").tag("de")
                            }
                        }
                        .disabled(!AIPolisher.isModelLocal)
                        if !AIPolisher.isModelLocal {
                            Text("Needs the AI model (~335 MB). Enable Polish with AI or download it from the setup guide first.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Divider()
                    switchRow("Sound on start and stop", isOn: $settings.sound)
                    let _ = refreshTick
                }

                section("Hotkey") {
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
                            .secondaryButton()
                            Button("Retry hotkey") {
                                _ = appState.installHotkeys()
                            }
                            .secondaryButton()
                        }
                    }
                }

                section("How to use") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Hold right ⌘: dictate, release to paste the text.")
                        Text("Quick tap on right ⌘: start; tap again to paste.")
                        Text("Text is typed wherever your cursor is, in any app.")
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                }

                section("Permissions") {
                    permissionRow("Microphone", ok: micOK())
                    permissionRow("Speech recognition", ok: speechOK())
                    permissionRow("Accessibility (for auto-paste)", ok: TextTyper.isTrusted())
                    if !TextTyper.isTrusted() {
                        HStack {
                            Button("Open Settings › Privacy › Accessibility") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .secondaryButton()
                            Button("Ask for permission") {
                                _ = TextTyper.isTrusted(prompt: true)
                                refreshTick += 1
                            }
                            .secondaryButton()
                        }
                    }
                    if !micOK() || !speechOK() {
                        Text("Permissions are requested automatically the first time you dictate.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Text("Note: if the app is rebuilt, macOS may ask for permissions again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
            }
            .padding(20)
        }
        .frame(minHeight: 460, idealHeight: 640)
        .background(GlassBackdrop())
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshTick += 1
        }
    }

    /// A titled glass card, the replacement for a grouped Form section.
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 6)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .card()
        }
    }

    /// Label on the left, pop-up menu on the right (the picker keeps its own
    /// accessibility label; only its visual label is hidden).
    private func pickerRow<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            control()
                .labelsHidden()
                .fixedSize()
        }
    }

    /// Label on the left, switch on the right, like a grouped Form row.
    private func switchRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
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
