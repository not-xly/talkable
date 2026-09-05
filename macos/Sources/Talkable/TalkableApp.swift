import SwiftUI

@main
struct TalkableApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState.shared
    @Environment(\.openWindow) private var openWindow
    static let openOnboarding = Notification.Name("talkable.open-onboarding")

    var body: some Scene {
        MenuBarExtra {
            Group {
                switch state.status {
                case .idle:
                    Text("Ready to dictate")
                case .recording:
                    Text("Recording…")
                case .transcribing:
                    Text("Transcribing…")
                case .error(let msg):
                    Text("Error: \(msg)")
                        .lineLimit(2)
                }
            }
            .font(.caption)
            .onReceive(NotificationCenter.default.publisher(for: Self.openOnboarding)) { _ in
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "onboarding")
            }
            Divider()
            Button(state.status == .recording ? "Stop and paste (right ⌘)" : "Start dictating (right ⌘)") {
                state.hotkeyPressed()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            Button("Cancel dictation") {
                state.cancel()
            }
            .disabled(!state.isDictating)
            Divider()
            Button("Getting started…") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "onboarding")
            }
            Button("Preferences…") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "preferences")
            }
            .keyboardShortcut(",")
            Divider()
            Button("Quit Talkable") {
                state.cancel()
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            switch state.status {
            case .recording:
                Image(systemName: "mic.fill")
            case .transcribing:
                Image(systemName: "waveform")
            case .error:
                Image(systemName: "exclamationmark.triangle")
            case .idle:
                Image(systemName: "mic")
            }
        }

        Window("Getting started", id: "onboarding") {
            OnboardingView()
        }
        .windowResizability(.contentSize)

        Window("Preferences", id: "preferences") {
            PreferencesView()
                .frame(width: 440)
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let onboardingPending = !UserDefaults.standard.bool(forKey: "onboardingComplete")
        let hotkeyOK = AppState.shared.installHotkeys()

        if !hotkeyOK && !onboardingPending {
            let alert = NSAlert()
            alert.messageText = "Missing the “Input Monitoring” permission"
            alert.informativeText = "For right ⌘ to start dictation, Talkable needs that permission. Grant it in Settings, then hit “Retry hotkey” in Preferences (or reopen the app)."
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                NSWorkspace.shared.open(url)
            }
        }

        if onboardingPending {
            // The first-run guide covers permissions; no need for the
            // modal alert on the very first launch.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                NotificationCenter.default.post(name: TalkableApp.openOnboarding, object: nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
