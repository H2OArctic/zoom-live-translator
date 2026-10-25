import Foundation

public enum RecognitionBackend: String, CaseIterable, Identifiable, Sendable {
    case fluid, apple, whisper
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .apple: "Apple · быстрый"
        case .whisper: "Whisper Turbo · экспериментальный"
        case .fluid: "FluidAudio · Parakeet v3"
        }
    }
}

public enum TranslationQuality {
    public static let recognitionHints = "Dev, UAT, production, FIX engine, market data, risk service, strategy runner, drop copy, heartbeat, stale data, reduce-only orders, pull requests, CI, commits, Ansible, GitHub Actions, SQLite, WAN, LAN, NOC, IPC, iceoryx, loopback, drawdown, L3."
    public static let defaultGlossary = """
    Technical software engineering and trading discussion. Dev = development environment; UAT = user acceptance testing; prod = production environment. FIX engine = движок FIX; execution report = отчёт об исполнении ордера; order = ордер, not customer purchase; market data = рыночные данные; PR = пул-реквест. Risk service, strategy runner, drop copy, heartbeat, stale data, reduce-only orders. PR = pull request, never public relations or public speaking. CI = continuous integration; commits = code commits. Ansible and GitHub Actions are names, not ordinary words. Preserve service names, personal names and identifiers. Do not guess missing words in the transcript.
    """

    public static func warnings(original: String, translated: String, pair: LanguagePair) -> [String] {
        var warnings: [String] = []
        let sourceNumbers = TranslationNumbers.values(in: pair.source == "en" ? TechnicalTranslation.englishInput(original) : original)
        if !sourceNumbers.isEmpty && sourceNumbers != TranslationNumbers.values(in: translated) {
            warnings.append("Проверь числа: они могли измениться в переводе")
        }
        if pair == .englishToRussian {
            if original.range(of: #"\b(not|never|no|cannot|can't|don't|doesn't|didn't|won't|isn't|aren't|wasn't)\b"#, options: [.regularExpression, .caseInsensitive]) != nil,
               translated.range(of: #"\b(не[а-яё]*|нет|нельзя|никогда|без)\b"#, options: [.regularExpression, .caseInsensitive]) == nil {
                warnings.append("Проверь отрицание: оно могло потеряться")
            }
            if original.range(of: #"\bAlice\b"#, options: [.regularExpression, .caseInsensitive]) != nil,
               !translated.localizedCaseInsensitiveContains("Алиса"), !translated.localizedCaseInsensitiveContains("Alice") {
                warnings.append("Проверь имя Alice: оно могло измениться")
            }
        }
        return warnings
    }
}

public struct RecognizedPhrase: Sendable, Equatable {
    public var text: String
    public var speaker: String?
    public let tracking: Bool
    public let pair: LanguagePair
    public init(text: String, speaker: String? = nil, tracking: Bool = false, pair: LanguagePair) {
        self.text = text; self.speaker = speaker; self.tracking = tracking; self.pair = pair
    }
}

public struct PhraseBuffer: Sendable {
    public private(set) var phrase: RecognizedPhrase?
    public private(set) var deadline: Date?
    private var started: Date?
    public init() {}

    public mutating func append(_ value: RecognizedPhrase, at now: Date = Date()) -> RecognizedPhrase? {
        var ready: RecognizedPhrase?
        if let current = phrase, current.pair != value.pair || current.tracking != value.tracking ||
            (current.speaker != nil && value.speaker != nil && current.speaker != value.speaker) ||
            current.text.count + value.text.count > 600 || (deadline.map { $0 <= now } ?? false) {
            ready = take()
        }
        if var current = phrase {
            current.text += " " + value.text
            if current.speaker != value.speaker { current.speaker = nil }
            phrase = current
        } else { phrase = value; started = now }
        touch(at: now)
        return ready
    }

    public mutating func touch(at now: Date = Date()) {
        guard let started, phrase != nil else { return }
        let text = phrase?.text ?? ""
        let complete = text.last.map { ".!?".contains($0) } ?? false
        let short = text.split(whereSeparator: \.isWhitespace).count <= 2
        deadline = min(now.addingTimeInterval(complete && !short ? 0.85 : 3.2), started.addingTimeInterval(6))
    }

    public mutating func take() -> RecognizedPhrase? {
        defer { phrase = nil; deadline = nil; started = nil }
        return phrase
    }
}

public enum RecognitionVocabulary {
    public static func parse(_ text: String) -> [String] {
        var seen = Set<String>()
        return Array(text.prefix(3000).components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64)) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }.prefix(64))
    }
}
