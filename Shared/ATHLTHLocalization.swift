import Foundation

enum ATHLTHLocalization {
    private static var selectedLocale: Locale {
        let value =
            UserDefaults.standard.string(
                forKey: "settings.language"
            )

        guard let value,
              value != "system",
              !value.isEmpty
        else {
            return .autoupdatingCurrent
        }

        return Locale(identifier: value)
    }

    static func string(
        _ key: String.LocalizationValue
    ) -> String {
        String(
            localized: key,
            locale: selectedLocale
        )
    }
}
