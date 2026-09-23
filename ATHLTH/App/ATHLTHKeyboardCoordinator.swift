import UIKit

@MainActor
final class ATHLTHKeyboardCoordinator {
    static let shared = ATHLTHKeyboardCoordinator()

    private var keyboardObserver: NSObjectProtocol?

    private init() {}

    func install() {
        guard keyboardObserver == nil else { return }

        // SwiftUI Form, List and ScrollView are backed by UIScrollView.
        // Interactive dismissal makes dragging the keyboard down work
        // consistently across ATHLTH without every screen implementing it.
        UIScrollView.appearance().keyboardDismissMode = .interactive

        keyboardObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardDidShowNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.attachDoneButtonToCurrentResponder()
            }
        }
    }

    private func attachDoneButtonToCurrentResponder() {
        guard let responder = UIResponder.athlthCurrentFirstResponder() else {
            return
        }

        if let textField = responder as? UITextField {
            guard textField.inputAccessoryView?.tag != Self.toolbarTag else {
                return
            }

            textField.inputAccessoryView = makeToolbar()
            textField.reloadInputViews()
            return
        }

        if let textView = responder as? UITextView {
            guard textView.inputAccessoryView?.tag != Self.toolbarTag else {
                return
            }

            textView.inputAccessoryView = makeToolbar()
            textView.reloadInputViews()
        }
    }

    private func makeToolbar() -> UIToolbar {
        let toolbar = UIToolbar()
        toolbar.tag = Self.toolbarTag
        toolbar.sizeToFit()

        let spacer = UIBarButtonItem(
            barButtonSystemItem: .flexibleSpace,
            target: nil,
            action: nil
        )
        let done = UIBarButtonItem(
            title: "Done",
            style: .done,
            target: self,
            action: #selector(doneTapped)
        )

        toolbar.items = [spacer, done]
        return toolbar
    }

    @objc
    private func doneTapped() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private static let toolbarTag = 0xA7_11_7
}

private var athlthCapturedFirstResponder: UIResponder?

private extension UIResponder {
    @objc
    func athlthCaptureFirstResponder() {
        athlthCapturedFirstResponder = self
    }

    @MainActor
    static func athlthCurrentFirstResponder() -> UIResponder? {
        athlthCapturedFirstResponder = nil

        UIApplication.shared.sendAction(
            #selector(athlthCaptureFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )

        return athlthCapturedFirstResponder
    }
}
