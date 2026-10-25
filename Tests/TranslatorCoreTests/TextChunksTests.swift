import Testing
@testable import TranslatorCore

@Test func longSpeechRetainsWordsAndFitsRenderingChunks() {
    let text = Array(repeating: "Проверим перевод: звук должен сохраняться полностью, даже когда фраз много!", count: 50).joined(separator: " ")
    let chunks = TextChunks.split(text, limit: 180)
    #expect(chunks.count > 3)
    #expect(chunks.allSatisfy { $0.count <= 180 })
    #expect(chunks.joined(separator: " ").split(whereSeparator: \.isWhitespace) == text.split(whereSeparator: \.isWhitespace))
}

@Test func splitsLongTokensWithoutLosingUnicode() {
    let text = String(repeating: "👩🏽‍💻", count: 400)
    let chunks = TextChunks.split(text, limit: 180)
    #expect(chunks.joined() == text)
    #expect(chunks.allSatisfy { $0.count <= 180 })
}

@Test func queuedJobRetainsEngineAndLanguageSelection() {
    var pair = LanguagePair.russianToEnglish
    let job = TranslationJob(direction: .incoming, text: "Привет", languagePair: pair, backend: .ollama)
    pair = .englishToRussian
    var queue = TranslationQueue()
    queue.enqueue(job)
    let received = queue.next()
    #expect(received?.languagePair == .russianToEnglish)
    #expect(received?.backend == .ollama)
    #expect(pair == .englishToRussian)
}
