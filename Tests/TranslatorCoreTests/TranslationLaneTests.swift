import Foundation
import Testing
@testable import TranslatorCore

@Test(.timeLimit(.minutes(1))) @MainActor
func blockedIncomingTranslationDoesNotBlockMicrophone() async {
    let incoming = TranslationLane()
    let outgoing = TranslationLane()
    let (release, releaseContinuation) = AsyncStream<Void>.makeStream()
    let (results, resultContinuation) = AsyncStream<Direction>.makeStream()
    let acceptedIncoming = incoming.enqueue(TranslationJob(direction: .incoming, text: "Hello")) { _ in
        for await _ in release { break }
        resultContinuation.yield(.incoming)
    }
    let acceptedOutgoing = outgoing.enqueue(TranslationJob(direction: .outgoing, text: "Привет")) { _ in
        resultContinuation.yield(.outgoing)
    }
    #expect(acceptedIncoming && acceptedOutgoing)
    var iterator = results.makeAsyncIterator()
    let first = await iterator.next()
    #expect(first == .outgoing)
    releaseContinuation.yield(())
    let second = await iterator.next()
    #expect(second == .incoming)
    releaseContinuation.finish()
    resultContinuation.finish()
}
