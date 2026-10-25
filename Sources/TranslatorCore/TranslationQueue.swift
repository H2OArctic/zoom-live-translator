import Foundation

public enum Direction: String, CaseIterable, Sendable, Identifiable {
    case incoming, outgoing

    public var id: String { rawValue }
    public var title: String { self == .incoming ? "Звук приложения" : "Микрофон" }
    public var defaultLanguagePair: LanguagePair { self == .incoming ? .englishToRussian : .russianToEnglish }
}

public enum LanguagePair: String, CaseIterable, Sendable, Identifiable {
    case englishToRussian, russianToEnglish

    public var id: String { rawValue }
    public var source: String { self == .englishToRussian ? "en" : "ru" }
    public var target: String { self == .englishToRussian ? "ru" : "en" }
    public var locale: String { self == .englishToRussian ? "en-US" : "ru-RU" }
    public var voiceLocale: String { self == .englishToRussian ? "ru-RU" : "en-US" }
    public var title: String { self == .englishToRussian ? "EN → RU" : "RU → EN" }
}

public struct TranslationJob: Sendable, Equatable {
    public let id: UUID
    public let direction: Direction
    public let languagePair: LanguagePair
    public let text: String
    public let backend: TranslationBackend
    public let context: [String]
    public let glossary: String
    public let createdAt: Date

    public init(direction: Direction, text: String, languagePair: LanguagePair? = nil, backend: TranslationBackend = .apple, context: [String] = [], glossary: String = "") {
        self.id = UUID()
        self.direction = direction
        self.languagePair = languagePair ?? direction.defaultLanguagePair
        self.text = text
        self.backend = backend
        self.context = context
        self.glossary = glossary
        self.createdAt = Date()
    }
}

public struct TranslationQueue: Sendable {
    private var jobs: [TranslationJob] = []
    public let capacity: Int
    public var count: Int { jobs.count }

    public init(capacity: Int = 32) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    @discardableResult
    public mutating func enqueue(_ job: TranslationJob) -> Bool {
        guard !job.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              jobs.count < capacity else { return false }
        jobs.append(job)
        return true
    }

    public mutating func next() -> TranslationJob? {
        jobs.isEmpty ? nil : jobs.removeFirst()
    }

    public mutating func removeAll() { jobs.removeAll() }
}
