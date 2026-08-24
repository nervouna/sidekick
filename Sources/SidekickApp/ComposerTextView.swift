import AppKit
import SwiftUI

struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    /// Monotonic counter; every increment asks the text view to take focus.
    /// A counter rather than a Bool so repeat requests (reopening the popover
    /// twice without typing) still register.
    let focusRequest: Int
    let onSubmit: () -> Void
    let onDismiss: () -> Void

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
        textView.onDismiss = onDismiss
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
        textView.onDismiss = onDismiss
        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            focus(textView)
        }
        // While an IME composition (e.g. pinyin) is in progress, the binding
        // round-trip can lag a keystroke behind. Overwriting `.string` here
        // would cancel the in-flight composition and drop the marked text.
        guard !textView.hasMarkedText() else { return }
        if textView.string != text { textView.string = text }
    }

    /// The popover's window may not exist yet on the pass that carries a new
    /// focus request, so fall back to the next runloop turn once.
    private func focus(_ textView: SubmitTextView) {
        if textView.window?.makeFirstResponder(textView) == true { return }
        DispatchQueue.main.async { [weak textView] in
            guard let textView else { return }
            textView.window?.makeFirstResponder(textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView
        var lastFocusRequest = 0
        init(parent: ComposerTextView) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }
    }
}

private final class SubmitTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onDismiss: (() -> Void)?

    // Esc closes the popover. AppKit routes Esc here only once no IME
    // candidate window is open — the input method consumes the first press to
    // cancel its own composition, which is the behavior we want.
    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }

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
