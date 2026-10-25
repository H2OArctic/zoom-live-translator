import Testing
@testable import TranslatorCore

@Test func commitsStablePrefixAndFlushesTailExactlyOnce() throws {
    var cursor = TranscriptCommitter()
    let first = cursor.advance("Alice will deploy the FIX engine")
    #expect(first.text == "Alice will deploy")
    #expect(first.draft == "the FIX engine")
    let second = cursor.advance("Alice will deploy the FIX engine to UAT.")
    #expect(second.text == "the FIX")
    let final = cursor.advance("Alice will deploy the FIX engine to UAT.", final: true)
    #expect(final.text == "engine to UAT.")
    #expect(cursor.advance("Alice will deploy the FIX engine to UAT.", final: true).text.isEmpty)
}

@Test func reconcilesRewrittenCommittedWordsWithoutRepeatingTheTranslation() {
    var cursor = TranscriptCommitter()
    _ = cursor.advance("Alice will deploy the service today")
    let revised = cursor.advance("Robert will deploy the service today.", final: true)
    #expect(revised.revised)
    #expect(revised.text == "the service today.")
    #expect(cursor.advance("Robert will deploy the service today.", final: true).text.isEmpty)
}

@Test func reconcilesInsertionsDeletionsAndTemporaryRetractions() {
    var insertion = TranscriptCommitter()
    _ = insertion.advance("We reviewed the service logs today")
    #expect(insertion.advance("We have reviewed the service logs today.", final: true).text == "service logs today.")
    var deletion = TranscriptCommitter()
    _ = deletion.advance("We have reviewed the service logs today")
    #expect(deletion.advance("We reviewed the service logs today.", final: true).text == "service logs today.")
    var retraction = TranscriptCommitter()
    _ = retraction.advance("We reviewed the service logs today")
    #expect(retraction.advance("We reviewed").text.isEmpty)
    #expect(retraction.advance("", final: false).text.isEmpty)
    #expect(retraction.advance("We reviewed the service logs today.", final: true).text == "service logs today.")
}

@Test func revisionInsideTheCommittedBoundaryKeepsTheUntranslatedTail() {
    var cursor = TranscriptCommitter()
    _ = cursor.advance("The strategy was halted but risk returned armed")
    let result = cursor.advance("The strategy is halted while risk returned armed.", final: true)
    #expect(result.revised)
    #expect(result.text == "risk returned armed.")
}

@Test func boundsAudioBySampleCountAndReportsOverflowOnlyOnce() async {
    let input = BufferedPCM(capacity: 8)
    #expect(input.append([1, 2, 3, 4]) == .accepted)
    var iterator = input.stream.makeAsyncIterator()
    let first = await iterator.next() ?? []
    input.consumed(first)
    #expect(input.append([5, 6, 7, 8, 9]) == .accepted)
    #expect(input.append([10, 11, 12, 13]) == .overflow)
    #expect(input.append([14]) == .closed)
    var received = first
    while let samples = await iterator.next() { received.append(contentsOf: samples) }
    #expect(received == [1, 2, 3, 4, 5, 6, 7, 8, 9])
}

@Test func phraseModeKeepsNegationWithItsObjectAndFlushesShortUtterances() throws {
    var cursor = TranscriptCommitter()
    let first = cursor.advance("We don't use Ansible and we", preferPhrases: true)
    #expect(first.text.isEmpty)
    #expect(first.draft == "We don't use Ansible and we")
    let next = cursor.advance("We don't use Ansible, and we use GitHub Actions.", preferPhrases: true)
    #expect(next.text.isEmpty)
    let final = cursor.advance("We don't use Ansible, and we use GitHub Actions.", final: true)
    #expect(final.text == "We don't use Ansible, and we use GitHub Actions.")
}

@Test func standaloneBoundaryPunctuationDoesNotLookLikeAWordRevision() throws {
    var cursor = TranscriptCommitter()
    _ = cursor.advance("We reviewed three pull requests . Alice will deploy to UAT.")
    let final = cursor.advance("We reviewed three pull requests. Alice will deploy to UAT.", final: true)
    #expect(final.text == "deploy to UAT.")
}

@Test func recognitionVocabularyTrimsDeduplicatesAndBoundsUserInput() {
    #expect(RecognitionVocabulary.parse(" Ansible, FIX engine\nansible, , UAT ") == ["Ansible", "FIX engine", "UAT"])
    let terms = RecognitionVocabulary.parse((0..<100).map { "term\($0)" }.joined(separator: ","))
    #expect(terms.count == 64)
    #expect(RecognitionVocabulary.parse(String(repeating: "a", count: 1000)).first?.count == 64)
}

@Test func finalEmptySnapshotFlushesTheUntranslatedTail() {
    var cursor = TranscriptCommitter()
    _ = cursor.advance("We reviewed the service logs today")
    #expect(cursor.advance("", final: true).text == "service logs today")
    #expect(cursor.advance("", final: true).text.isEmpty)
}

@Test func largeAmbiguousRevisionIsBoundedAndReportedWithoutRepeatingOldText() {
    var cursor = TranscriptCommitter()
    let old = (0..<600).map { "old\($0)" }.joined(separator: " ")
    let new = (0..<600).map { "new\($0)" }.joined(separator: " ")
    _ = cursor.advance(old)
    let result = cursor.advance(new, final: true)
    #expect(result.revised && result.uncertain)
    #expect(result.text.isEmpty)
}
