import NaturalLanguage

/// Service for detecting the language of text
struct LanguageDetector {

    /// Supported languages for this app
    enum Language: String, CaseIterable, Identifiable {
        case german = "de"
        case english = "en"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .german: return "German"
            case .english: return "English"
            }
        }

        var flag: String {
            switch self {
            case .german: return "🇩🇪"
            case .english: return "🇬🇧"
            }
        }
    }

    /// Detect the language of the given text
    /// - Parameter text: The text to analyze
    /// - Returns: The detected language, defaulting to English if uncertain
    static func detect(text: String) -> Language {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)

        guard let dominantLanguage = recognizer.dominantLanguage else {
            return .english
        }

        switch dominantLanguage {
        case .german:
            return .german
        case .english:
            return .english
        default:
            // For other languages, check if German or English has high probability
            let hypotheses = recognizer.languageHypotheses(withMaximum: 2)

            if let germanProb = hypotheses[.german], germanProb > 0.3 {
                return .german
            }

            // Default to English
            return .english
        }
    }
}
