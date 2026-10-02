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

    static func format(
        _ key: String.LocalizationValue,
        _ arguments: CVarArg...
    ) -> String {
        String(
            format: string(key),
            locale: selectedLocale,
            arguments: arguments
        )
    }

    static var isNorwegian: Bool {
        let identifier =
            selectedLocale
                .language
                .languageCode?
                .identifier
                .lowercased()

        return identifier == "nb" ||
            identifier == "no" ||
            identifier == "nn"
    }

    static func choose(
        english: String,
        norwegian: String
    ) -> String {
        isNorwegian
            ? norwegian
            : english
    }

    static func format(
        english: String,
        norwegian: String,
        _ arguments: CVarArg...
    ) -> String {
        String(
            format:
                isNorwegian
                    ? norwegian
                    : english,
            locale: selectedLocale,
            arguments: arguments
        )
    }

    static func counted(
        _ count: Int,
        englishSingular: String,
        englishPlural: String,
        norwegianSingular: String,
        norwegianPlural: String
    ) -> String {
        let noun =
            count == 1
                ? choose(
                    english:
                        englishSingular,
                    norwegian:
                        norwegianSingular
                )
                : choose(
                    english:
                        englishPlural,
                    norwegian:
                        norwegianPlural
                )

        return "\(count) \(noun)"
    }
}
