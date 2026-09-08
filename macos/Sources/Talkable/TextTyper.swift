import AppKit
import ApplicationServices

/// Types text by faking Unicode keyboard events in the focused app.
/// Without the Accessibility permission, copies to the clipboard instead.
final class TextTyper {
    /// Checks trust, prompting the user once when needed.
    static func isTrusted(prompt: Bool = false) -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    func type(_ text: String, completion: ((Bool) -> Void)? = nil) {
        guard Self.isTrusted(prompt: true) else {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
            completion?(false)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            guard let source = CGEventSource(stateID: .hidSystemState) else {
                DispatchQueue.main.async { completion?(false) }
                return
            }
            let units = Array(text)
            var i = 0
            while i < units.count {
                let end = min(i + 20, units.count)
                let chunk = String(units[i..<end])
                let utf16 = Array(chunk.utf16)
                func event(_ keyDown: Bool) -> CGEvent? {
                    let e = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown)
                    e?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
                    return e
                }
                event(true)?.post(tap: .cghidEventTap)
                usleep(6_000)
                event(false)?.post(tap: .cghidEventTap)
                i = end
                usleep(8_000)
            }
            DispatchQueue.main.async { completion?(true) }
        }
    }
}
