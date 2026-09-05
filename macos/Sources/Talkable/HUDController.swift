import AppKit

/// Unobtrusive floating panel showing the dictation status: a red recording
/// dot plus live partial text. When the text gets long, the area auto-scrolls
/// to always show the latest words.
final class HUDController {
    private let panel: NSPanel
    private let dot = DotView()
    private let textArea: NSTextView
    private var hideWork: DispatchWorkItem?

    private final class DotView: NSView {
        var color: NSColor = .systemRed { didSet { layer?.backgroundColor = color.cgColor } }
        override func layout() {
            super.layout()
            wantsLayer = true
            layer?.cornerRadius = bounds.width / 2
            layer?.backgroundColor = color.cgColor
        }
    }

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 88),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hasShadow = true

        let background = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 340, height: 88))
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true

        dot.frame = NSRect(x: 18, y: 38, width: 12, height: 12)
        dot.wantsLayer = true
        background.addSubview(dot)

        let scroll = NSScrollView(frame: NSRect(x: 42, y: 10, width: 284, height: 68))
        scroll.hasVerticalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false

        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 284, height: 68))
        text.isEditable = false
        text.isSelectable = false
        text.drawsBackground = false
        text.textContainerInset = .zero
        text.autoresizingMask = [.width]
        scroll.documentView = text
        textArea = text
        background.addSubview(scroll)

        panel.contentView = background
    }

    private func update(_ text: String) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.white,
        ]
        textArea.textStorage?.setAttributedString(
            NSAttributedString(string: text, attributes: attributes)
        )
        textArea.layoutManager?.ensureLayout(for: textArea.textContainer!)
        textArea.scrollToEndOfDocument(nil)
    }

    private func show() {
        hideWork?.cancel()
        hideWork = nil
        position()
        panel.orderFrontRegardless()
    }

    private func position() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let width = panel.frame.width
        let x = visible.maxX - width - 16
        let y = visible.maxY - panel.frame.height - 8
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func showRecording() {
        dot.color = .systemRed
        update("Listening…")
        show()
    }

    func showText(_ text: String) {
        guard panel.isVisible else { return }
        update(text.isEmpty ? "Listening…" : text)
    }

    func showTranscribing() {
        dot.color = .systemGray
        update("Transcribing…")
    }

    func showPolishing() {
        dot.color = .systemPurple
        update("Polishing with local AI… (downloads the model on first use)")
        show()
    }

    func showError(_ message: String) {
        dot.color = .systemYellow
        update(message)
        show()
        let work = DispatchWorkItem { [weak self] in self?.panel.orderOut(nil) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        hideWork = nil
        panel.orderOut(nil)
    }
}
