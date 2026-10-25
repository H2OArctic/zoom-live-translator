import Foundation
import Testing
@testable import TranslatorCore

@Test func normalizesOnlyExplicitTechnicalIdentifiersAndSpokenDecimals() {
    #expect(TechnicalTranslation.englishInput("a fixed engine issue two ninety?") == "a FIX engine issue #290?")
    #expect(TechnicalTranslation.englishInput("risk service issue or a fixed engine two ninety?") == "risk service issue or a FIX engine issue #290?")
    #expect(TechnicalTranslation.englishInput("a fixed engine two ninety") == "a FIX engine two ninety")
    #expect(TechnicalTranslation.englishInput("issue two sixty eight and tag one fifty") == "issue #268 and tag 150")
    #expect(TechnicalTranslation.englishInput("FIX four four and FIX42, version four point two.") == "FIX 4.4 and FIX 4.2, version 4.2.")
    #expect(TechnicalTranslation.englishInput("prod O two and prod oh three") == "PROD02 and PROD03")
    #expect(TechnicalTranslation.englishInput("two ninety, two accounts, WordPress, a van, L free data") == "two ninety, two accounts, WordPress, a van, L free data")
    #expect(TechnicalTranslation.terminology(for: "Please fix a bug and look up the result.").isEmpty)
}

@Test func comparesProtocolVersionsAndIssueNumbersInEquivalentForms() {
    #expect(TranslationQuality.warnings(original: "Using four point two.", translated: "Используем 4.2.", pair: .englishToRussian).isEmpty)
    #expect(TranslationQuality.warnings(original: "FIX engine issue two ninety", translated: "Задача 290 движка FIX", pair: .englishToRussian).isEmpty)
    #expect(!TranslationQuality.warnings(original: "FIX engine issue two ninety", translated: "Движок FIX версии 90", pair: .englishToRussian).isEmpty)
    #expect(!TranslationQuality.warnings(original: "Using FIX four two", translated: "Используем FIX 42", pair: .englishToRussian).isEmpty)
}

@Test func comparesGroupedTradingQuantitiesWithoutLosingPerOrderAmounts() {
    #expect(TranslationNumbers.values(in: "a million euro and eight hundred thousand each") == ["1000000", "800000"])
    #expect(TranslationNumbers.values(in: "миллион евро и 800 000 каждый") == ["1000000", "800000"])
    #expect(TranslationNumbers.values(in: "800k and 800\u{202f}000 and 800\u{00a0}000") == ["800000"])
    #expect(TranslationNumbers.values(in: "2 and 4") == ["2", "4"])
}

@Test func longTechnicalClauseWaitsForItsObjectInsteadOfEighteenWordCut() {
    var cursor = TranscriptCommitter()
    let sentence = "We need to confirm whether both independent FIX sessions on the two separate hosts can share the same trading account"
    #expect(cursor.advance(sentence, preferPhrases: true).text.isEmpty)
    #expect(cursor.advance(sentence + ".", final: true, preferPhrases: true).text == sentence + ".")
}

@Test func unfinishedTechnicalPhraseCanJoinTheNextThreeSecondWindow() {
    let start = Date(timeIntervalSince1970: 100)
    var buffer = PhraseBuffer()
    _ = buffer.append(RecognizedPhrase(text: "not just the available position", pair: .englishToRussian), at: start)
    buffer.touch(at: start.addingTimeInterval(2.9))
    #expect(buffer.append(RecognizedPhrase(text: "but the working orders as well.", pair: .englishToRussian), at: start.addingTimeInterval(3.5)) == nil)
    #expect(buffer.take()?.text == "not just the available position but the working orders as well.")
}
