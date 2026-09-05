import AppKit
import Carbon.HIToolbox

/// Listens to the chosen key (right ⌘ by default) through an observe-only
/// CGEventTap. Requires the “Input Monitoring” permission. Unlike F5/F6,
/// right ⌘ triggers no system function.
final class HotkeyManager {
    private static var instance: HotkeyManager?

    private let keyCode: UInt32
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var watchdog: Timer?
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    init(keyCode: UInt32) {
        self.keyCode = keyCode
    }

    func install() -> Bool {
        guard tap == nil else { return true }
        HotkeyManager.instance = self
        #if DEBUG
        NSLog("Talkable: CGPreflightListenEventAccess=\(CGPreflightListenEventAccess())")
        #endif
        // Modifier keys (⌘) don't produce keyDown/keyUp, only flagsChanged.
        let mask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue)
                | (1 << CGEventType.keyUp.rawValue)
                | (1 << CGEventType.flagsChanged.rawValue)
        )
        guard let newTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, _ -> Unmanaged<CGEvent>? in
                guard let instance = HotkeyManager.instance else {
                    return Unmanaged.passUnretained(event)
                }
                let code = event.getIntegerValueField(.keyboardEventKeycode)
                if code == Int64(instance.keyCode) {
                    switch type {
                    case .keyDown, .keyUp:
                        DispatchQueue.main.async { instance.onKeyDown?() }
                    case .flagsChanged:
                        // Right ⌘: flagsChanged fires on press (with the ⌘
                        // flag set) and on release (flag cleared).
                        let pressed = event.flags.contains(.maskCommand)
                        #if DEBUG
                        NSLog("Talkable: right ⌘ \(pressed ? "pressed" : "released")")
                        #endif
                        DispatchQueue.main.async {
                            if pressed {
                                instance.onKeyDown?()
                            } else {
                                instance.onKeyUp?()
                            }
                        }
                    default:
                        break
                    }
                }
                // Listen-only: the event keeps flowing normally.
                return Unmanaged.passUnretained(event)
            },
            userInfo: nil
        ) else {
            #if DEBUG
            NSLog("Talkable: tapCreate FAILED — missing Input Monitoring permission (or reopen the app)")
            #endif
            return false
        }

        #if DEBUG
        NSLog("Talkable: tap created OK (keycode \(keyCode), right ⌘)")
        #endif
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        tap = newTap
        runLoopSource = source

        // The system may disable the tap if the callback ever lags;
        // this watchdog re-enables it on its own.
        watchdog = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self, let tap = self.tap else { return }
            if !CGEvent.tapIsEnabled(tap: tap) {
                NSLog("Talkable: tap disabled — re-enabling")
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        return true
    }
}
