import Foundation

enum ATHLTHLegalIdentity {
    private static func infoString(_ key: String) -> String? {
        guard let value = Bundle.main.object(
            forInfoDictionaryKey: key
        ) as? String else {
            return nil
        }

        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmed.isEmpty,
              !trimmed.contains("$(")
        else {
            return nil
        }

        return trimmed
    }

    static var operatorName: String? {
        infoString("ATHLTHLegalOperatorName")
    }

    static var privacyContactEmail: String? {
        infoString("ATHLTHPrivacyContactEmail")
    }

    static var supportURL: URL? {
        guard let raw = infoString("ATHLTHSupportURL") else {
            return nil
        }
        return URL(string: raw)
    }

    static var isFullyConfigured: Bool {
        operatorName != nil && privacyContactEmail != nil
    }

    static var controllerStatement: String {
        if let operatorName {
            return "\(operatorName) is the data controller responsible for ATHLTH."
        }

        return "The developer or seller identified on the ATHLTH App Store product page is the data controller responsible for ATHLTH."
    }

    static var privacyContactStatement: String {
        if let privacyContactEmail {
            return "Privacy questions, rights requests and data-protection inquiries can be sent to \(privacyContactEmail)."
        }

        return "Privacy questions, rights requests and data-protection inquiries can be submitted through the official ATHLTH support contact shown on the App Store product page."
    }

    static var termsContactStatement: String {
        if let operatorName, let privacyContactEmail {
            return "ATHLTH is operated by \(operatorName). Questions about these Terms can be sent to \(privacyContactEmail)."
        }

        return "ATHLTH is operated by the developer or seller identified on the App Store product page. Questions about these Terms can be submitted through the official ATHLTH support contact shown there."
    }
}
