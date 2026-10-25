import Foundation
import Testing
@testable import TranslatorCore

@Test func joinsRelatedFragmentsButKeepsSpeakerAndLanguageBoundaries() {
    let start = Date(timeIntervalSince1970: 100)
    var buffer = PhraseBuffer()
    #expect(buffer.append(RecognizedPhrase(text: "We haven't got the gateway", speaker: "Alice", pair: .englishToRussian), at: start) == nil)
    #expect(buffer.append(RecognizedPhrase(text: "set up there.", speaker: "Alice", pair: .englishToRussian), at: start.addingTimeInterval(0.7)) == nil)
    let ready = buffer.append(RecognizedPhrase(text: "Okay.", speaker: "Bob", pair: .englishToRussian), at: start.addingTimeInterval(0.9))
    #expect(ready?.text == "We haven't got the gateway set up there.")
    #expect(ready?.speaker == "Alice")
    #expect(buffer.take()?.speaker == "Bob")
    #expect(buffer.phrase == nil)
}

@Test func partialResultsCannotDelayFinalTextIndefinitely() {
    let start = Date(timeIntervalSince1970: 100)
    var buffer = PhraseBuffer()
    _ = buffer.append(RecognizedPhrase(text: "First fragment", pair: .englishToRussian), at: start)
    buffer.touch(at: start.addingTimeInterval(3.9))
    #expect(buffer.deadline == start.addingTimeInterval(6))
    let ready = buffer.append(RecognizedPhrase(text: "Next fragment", pair: .englishToRussian), at: start.addingTimeInterval(6.1))
    #expect(ready?.text == "First fragment")
    #expect(buffer.phrase?.text == "Next fragment")
}

@Test func uncertainSpeakerDoesNotAcquireSomeoneElsesName() {
    var buffer = PhraseBuffer()
    _ = buffer.append(RecognizedPhrase(text: "One", speaker: "Alice", tracking: true, pair: .englishToRussian))
    _ = buffer.append(RecognizedPhrase(text: "two", tracking: true, pair: .englishToRussian))
    #expect(buffer.take()?.speaker == nil)
}

@Test func warnsAboutChangedNumbersNegationAndAliceIdentity() {
    #expect(!TranslationQuality.warnings(original: "30 reports in 10 seconds", translated: "30 отчётов за 20 секунд", pair: .englishToRussian).isEmpty)
    #expect(!TranslationQuality.warnings(original: "We do not use Ansible.", translated: "Мы используем Ansible.", pair: .englishToRussian).isEmpty)
    #expect(!TranslationQuality.warnings(original: "Alice, anything to add?", translated: "Роберт, есть дополнения?", pair: .englishToRussian).isEmpty)
    #expect(TranslationQuality.warnings(original: "Alice, we do not need 30 reports.", translated: "Алиса, нам не нужны 30 отчётов.", pair: .englishToRussian).isEmpty)
}

@Test func queuedTranslationRetainsItsContextAndGlossary() {
    var history = ["Previous sentence"]
    let job = TranslationJob(direction: .incoming, text: "Current", context: history, glossary: "PR = pull request")
    history.append("Later sentence")
    #expect(job.context == ["Previous sentence"])
    #expect(job.glossary == "PR = pull request")
}

@Test func allowsNextRecognitionWindowToCompleteAShortFragment() {
    let start = Date(timeIntervalSince1970: 100)
    var buffer = PhraseBuffer()
    _ = buffer.append(RecognizedPhrase(text: "в этом примере", pair: .russianToEnglish), at: start)
    #expect(buffer.deadline == start.addingTimeInterval(3.2))
    #expect(buffer.append(RecognizedPhrase(text: "тестовый сервис был halted", pair: .russianToEnglish), at: start.addingTimeInterval(3)) == nil)
    #expect(buffer.deadline == start.addingTimeInterval(6))
    #expect(buffer.take()?.text == "в этом примере тестовый сервис был halted")
}

@Test func detectsSpokenNumbersWithoutConfusingThousandsFormatting() {
    #expect(TranslationNumbers.values(in: "триста процентов, строка двести вторая и пример двести третий") == ["300", "202", "203"])
    #expect(TranslationNumbers.values(in: "sixty-sixth and two hundred third") == ["66", "203"])
    #expect(TranslationQuality.warnings(original: "21 тысяча", translated: "21,000", pair: .russianToEnglish).isEmpty)
    #expect(!TranslationQuality.warnings(original: "строка шестидесятая", translated: "sixty-sixth row", pair: .russianToEnglish).isEmpty)
    #expect(!TranslationQuality.warnings(original: "триста процентов", translated: "a waste of time", pair: .russianToEnglish).isEmpty)
    #expect(!TranslationQuality.warnings(original: "двести вторая", translated: "212th", pair: .russianToEnglish).isEmpty)
    #expect(TranslationNumbers.values(in: "one thousand two hundred third and 1,000.25") == ["1203", "1000.25"])
    #expect(TranslationNumbers.values(in: "2,5 and 0.25 and 1000") == ["2.5", "0.25", "1000"])
}

@Test func normalizesRussianNumeralsForTheModelWithoutChangingOtherWords() {
    #expect(TranslationNumbers.russianInput("строка шестьдесятая.") == "строка 60-я.")
    #expect(TranslationNumbers.russianInput("271-й, а двести вторая, двести третий") == "271-й, а 202-я, 203-й")
    #expect(TranslationNumbers.russianInput("нагрузка триста процентов") == "нагрузка 300 процентов")
    #expect(TranslationNumbers.russianInput("две семьдесят третья") == "две 73-я")
    #expect(TranslationNumbers.russianInput("в двадцать первом и двухсот третьем") == "в 21-м и двухсот третьем")
    #expect(TranslationNumbers.russianInput("один PR, 21 тысяча и QuestDB") == "один PR, 21 тысяча и QuestDB")
}

@Test func completeMeaningfulSentenceDoesNotWaitForTheNextWindow() {
    let start = Date(timeIntervalSince1970: 100)
    var buffer = PhraseBuffer()
    _ = buffer.append(RecognizedPhrase(text: "We don't use Ansible.", pair: .englishToRussian), at: start)
    #expect(buffer.deadline == start.addingTimeInterval(0.85))
}
