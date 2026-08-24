import AppKit
import SwiftUI

struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = SubmitTextView()
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        textView.isRichText = false
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textContainerInset = NSSize(width: 4, height: 5)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.string = text
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? SubmitTextView else { return }
        textView.onSubmit = onSubmit
        // While an IME composition (e.g. pinyin) is in progress, the binding
        // round-trip can lag a keystroke behind. Overwriting `.string` here
        // would cancel the in-flight composition and drop the marked text.
        guard !textView.hasMarkedText() else { return }
        if textView.string != text { textView.string = text }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView
        init(parent: ComposerTextView) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }
    }
}

private final class SubmitTextView: NSTextView {
    var onSubmit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        // While an IME candidate window is open, Return confirms the
        // candidate rather than submitting; let AppKit's input handling see it.
        if isReturn && !event.modifierFlags.contains(.shift) && !hasMarkedText() {
            onSubmit?()
        } else {
            super.keyDown(with: event)
        }
    }

    // AppKit doesn't reliably call the delegate's textDidChange for pure IME
    // composition previews, only for committed edits. Without this, the
    // SwiftUI-side placeholder and character count never react while typing
    // pinyin (or any other marked text) is in progress.
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))
    }

    override func unmarkText() {
        super.unmarkText()
        delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))
    }
}
