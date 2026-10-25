import Foundation
import Observation

@MainActor @Observable
package final class TranslationLane {
    private var queue = TranslationQueue()
    private var current: TranslationJob?
    private var task: Task<Void, Never>?
    private var generation = UUID()

    package init() {}

    package var count: Int { queue.count + (current == nil ? 0 : 1) }
    package var hasWork: Bool { count > 0 }
    package var waitingSince: Date? { current?.createdAt }

    package func enqueue(_ job: TranslationJob, process: @escaping @MainActor (TranslationJob) async -> Void) -> Bool {
        guard queue.enqueue(job) else { return false }
        guard task == nil else { return true }
        let token = generation
        task = Task { [weak self] in
            while let self, !Task.isCancelled, self.generation == token, let next = self.queue.next() {
                self.current = next
                await process(next)
                guard !Task.isCancelled, self.generation == token else { return }
                self.current = nil
            }
            guard let self, self.generation == token else { return }
            self.task = nil
        }
        return true
    }

    package func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        current = nil
        queue.removeAll()
    }
}
