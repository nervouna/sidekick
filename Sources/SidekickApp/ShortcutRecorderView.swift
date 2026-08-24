import AppKit
import SwiftUI
import SidekickCore

/// Click-to-record shortcut field. Reports every captured chord, valid or not;
/// validation and persistence belong to the caller.
struct ShortcutRecorder: NSViewRepresentable {
    let binding: HotKeyBinding
    let onRecord: (HotKeyBinding) -> Void

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.binding = binding
        view.onRecord = onRecord
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.binding = binding
        view.onRecord = onRecord
    }
}

final class RecorderView: NSView {
    var binding: HotKeyBinding = .default {
        didSet { needsDisplay = true }
    }
    var onRecord: ((HotKeyBinding) -> Void)?

    private var isRecording = false {
        didSet { needsDisplay = true }
    }
    private var liveModifiers: HotKeyModifiers = [] {
        didSet { needsDisplay = true }
    }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 26) }

    override func mouseDown(with event: NSEvent) {
        guard !isRecording else { return }
        window?.makeFirstResponder(self)
        liveModifiers = []
        isRecording = true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        let keyCode = event.keyCode
        if keyCode == HotKeyCode.escape {
            endRecording()
            return
        }
        if keyCode == HotKeyCode.delete {
            onRecord?(.default)
            endRecording()
            return
        }
        onRecord?(HotKeyBinding(
            keyCode: keyCode,
            modifiers: HotKeyModifiers(eventFlags: event.modifierFlags)
        ))
        endRecording()
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }
        liveModifiers = HotKeyModifiers(eventFlags: event.modifierFlags)
    }

    /// While recording, ⌘-chords would otherwise be consumed as menu key
    /// equivalents and never reach `keyDown`.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }

    override func resignFirstResponder() -> Bool {
        endRecording()
        return true
    }

    private func endRecording() {
        isRecording = false
        liveModifiers = []
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds.insetBy(dx: 0.5, dy: 0.5)
        let box = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.12) : .controlBackgroundColor).setFill()
        box.fill()
        (isRecording ? NSColor.controlAccentColor : .separatorColor).setStroke()
        box.lineWidth = isRecording ? 2 : 1
        box.stroke()

        let text = displayText as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: isRecording ? NSColor.secondaryLabelColor : NSColor.labelColor
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(
                x: bounds.midX - size.width / 2,
                y: bounds.midY - size.height / 2
            ),
            withAttributes: attributes
        )
    }

    private var displayText: String {
        guard isRecording else { return binding.displayString }
        return liveModifiers.isEmpty ? "按下快捷键…" : liveModifiers.displayString
    }
}
