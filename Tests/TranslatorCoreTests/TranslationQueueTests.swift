import Testing
@testable import TranslatorCore

@Test func preservesBothDirectionsInOrder() {
    var queue = TranslationQueue(capacity: 2)
    let first = TranslationJob(direction: .incoming, text: "Hello")
    let second = TranslationJob(direction: .outgoing, text: "Привет")
    let acceptedFirst = queue.enqueue(first)
    let acceptedSecond = queue.enqueue(second)
    let receivedFirst = queue.next()
    let receivedSecond = queue.next()
    let empty = queue.next()
    #expect(acceptedFirst)
    #expect(acceptedSecond)
    #expect(receivedFirst == first)
    #expect(receivedSecond == second)
    #expect(empty == nil)
}

@Test func rejectsOverflowWithoutDiscardingOlderSpeech() {
    var queue = TranslationQueue(capacity: 1)
    let first = TranslationJob(direction: .incoming, text: "First")
    let acceptedFirst = queue.enqueue(first)
    let acceptedOverflow = queue.enqueue(TranslationJob(direction: .outgoing, text: "Second"))
    #expect(acceptedFirst)
    #expect(!acceptedOverflow)
    #expect(queue.count == 1)
    let received = queue.next()
    #expect(received == first)
}

@Test func stopDiscardsPendingSpeech() {
    var queue = TranslationQueue()
    let accepted = queue.enqueue(TranslationJob(direction: .outgoing, text: "Привет"))
    #expect(accepted)
    queue.removeAll()
    let empty = queue.next()
    let acceptedWhitespace = queue.enqueue(TranslationJob(direction: .incoming, text: " \n "))
    #expect(empty == nil)
    #expect(!acceptedWhitespace)
}
