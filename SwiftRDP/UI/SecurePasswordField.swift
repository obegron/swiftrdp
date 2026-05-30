import AppKit
import SwiftUI

struct SecurePasswordField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var placeholder: String
    var onCommit: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused, onCommit: onCommit)
    }

    func makeNSView(context: Context) -> NSSecureTextField {
        let field = NSSecureTextField()
        field.placeholderString = placeholder
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .default
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.commit(_:))
        return field
    }

    func updateNSView(_ nsView: NSSecureTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        context.coordinator.onCommit = onCommit

        if isFocused, nsView.window?.firstResponder !== nsView.currentEditor() {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
                nsView.currentEditor()?.selectAll(nil)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding private var text: String
        @Binding private var isFocused: Bool
        var onCommit: () -> Void

        init(text: Binding<String>, isFocused: Binding<Bool>, onCommit: @escaping () -> Void) {
            _text = text
            _isFocused = isFocused
            self.onCommit = onCommit
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSecureTextField else {
                return
            }

            text = field.stringValue
        }

        @objc func commit(_ sender: NSSecureTextField) {
            text = sender.stringValue
            onCommit()
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            isFocused = true
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            isFocused = false
        }
    }
}
