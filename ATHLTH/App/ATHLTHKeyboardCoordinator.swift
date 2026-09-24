import UIKit

@MainActor
final class ATHLTHKeyboardCoordinator {
    static let shared = ATHLTHKeyboardCoordinator()

    private var keyboardObserver: NSObjectProtocol?

    private init() {}

    func install() {
        guard keyboardObserver == nil else { return }

        // SwiftUI Form, List and ScrollView are backed by UIScrollView.
        // Keep native interactive dismissal so users can also drag the
        // keyboard down anywhere ATHLTH uses a scrollable form.
        UIScrollView.appearance().keyboardDismissMode = .interactive

        keyboardObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardDidShowNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.attachDismissControlToCurrentResponder()
            }
        }
    }

    private func attachDismissControlToCurrentResponder() {
        guard let responder = UIResponder.athlthCurrentFirstResponder() else {
            return
        }

        if let textField = responder as? UITextField {
            guard textField.inputAccessoryView?.tag != Self.accessoryTag else {
                return
            }

            textField.inputAccessoryView = makeAccessoryBar()
            textField.reloadInputViews()
            return
        }

        if let textView = responder as? UITextView {
            guard textView.inputAccessoryView?.tag != Self.accessoryTag else {
                return
            }

            textView.inputAccessoryView = makeAccessoryBar()
            textView.reloadInputViews()
        }
    }

    private func makeAccessoryBar() -> UIView {
        let height: CGFloat = 36
        let container = UIView(
            frame: CGRect(x: 0, y: 0, width: 0, height: height)
        )
        container.tag = Self.accessoryTag
        container.autoresizingMask = [.flexibleWidth]
        container.backgroundColor = .secondarySystemBackground

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator.withAlphaComponent(0.45)

        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = "Hide keyboard"
        button.tintColor = .secondaryLabel

        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(
            systemName: "keyboard.chevron.compact.down"
        )
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: 17,
            weight: .semibold
        )
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 4,
            leading: 8,
            bottom: 4,
            trailing: 8
        )
        button.configuration = configuration
        button.addTarget(
            self,
            action: #selector(dismissKeyboardTapped),
            for: .touchUpInside
        )

        container.addSubview(separator)
        container.addSubview(button)

        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: container.topAnchor),
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),

            button.trailingAnchor.constraint(
                equalTo: container.safeAreaLayoutGuide.trailingAnchor,
                constant: -6
            ),
            button.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),
            button.heightAnchor.constraint(equalToConstant: 32)
        ])

        return container
    }

    @objc
    private func dismissKeyboardTapped() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private static let accessoryTag = 0xA7_11_7
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
