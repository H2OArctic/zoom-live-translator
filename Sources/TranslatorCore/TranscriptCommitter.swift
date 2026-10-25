import Foundation

public struct TranscriptCommitter: Sendable {
    private var previous: [String] = []
    private var committed = 0
    public init() {}

    public mutating func advance(_ snapshot: String, final: Bool = false, preferPhrases: Bool = false) -> (text: String, draft: String, revised: Bool, uncertain: Bool) {
        var words: [String] = []
        for token in snapshot.split(whereSeparator: \.isWhitespace) {
            let word = String(token)
            if word.unicodeScalars.allSatisfy({ CharacterSet.punctuationCharacters.contains($0) }) {
                if !words.isEmpty { words[words.count - 1] += word }
            } else { words.append(word) }
        }
        let old = previous.map(Self.normalized)
        let new = words.map(Self.normalized)
        if new.count < old.count && old.starts(with: new) {
            if final {
                let tail = previous.dropFirst(committed).joined(separator: " ")
                committed = previous.count
                return (tail, "", false, false)
            }
            return ("", previous.dropFirst(committed).joined(separator: " "), false, false)
        }
        var prefix = 0
        while prefix < min(old.count, new.count), old[prefix] == new[prefix] { prefix += 1 }
        let revised = prefix < committed
        var uncertain = false
        if revised {
            var suffix = 0
            while suffix < min(old.count, new.count) - prefix,
                  old[old.count - suffix - 1] == new[new.count - suffix - 1] { suffix += 1 }
            let oldEnd = old.count - suffix
            let newEnd = new.count - suffix
            if committed >= oldEnd {
                committed += newEnd - oldEnd
            } else if max(oldEnd - prefix, newEnd - prefix) <= 256 {
                committed = prefix + Self.alignedBoundary(Array(old[prefix..<oldEnd]), Array(new[prefix..<newEnd]), boundary: committed - prefix)
            } else {
                committed = newEnd
                uncertain = true
            }
        }
        var end = final ? words.count : max(committed, words.count - 3)
        if preferPhrases && !final {
            let boundary = (committed..<end).last { index in
                index - committed >= 3 && (words[index].last.map { ".!?".contains($0) } ?? false)
            }
            if let boundary { end = boundary + 1 }
            else if end - committed < 30 { end = committed }
        }
        let delta = words[committed..<end].joined(separator: " ")
        previous = words
        committed = end
        return (delta, words.dropFirst(end).joined(separator: " "), revised, uncertain)
    }

    private static func normalized(_ word: String) -> String {
        word.trimmingCharacters(in: .punctuationCharacters).lowercased()
    }

    private static func alignedBoundary(_ old: [String], _ new: [String], boundary: Int) -> Int {
        let width = new.count + 1
        var costs = [Int](repeating: 0, count: (old.count + 1) * width)
        for i in 0...old.count { costs[i * width] = i }
        for j in 0...new.count { costs[j] = j }
        if !old.isEmpty && !new.isEmpty {
            for i in 1...old.count {
                for j in 1...new.count {
                    costs[i * width + j] = min(costs[(i - 1) * width + j - 1] + (old[i - 1] == new[j - 1] ? 0 : 1),
                        costs[(i - 1) * width + j] + 1, costs[i * width + j - 1] + 1)
                }
            }
        }
        var i = old.count, j = new.count
        while i > boundary {
            if j > 0 && costs[i * width + j] == costs[(i - 1) * width + j - 1] + (old[i - 1] == new[j - 1] ? 0 : 1) {
                i -= 1; j -= 1
            } else if costs[i * width + j] == costs[(i - 1) * width + j] + 1 { i -= 1 }
            else { j -= 1 }
        }
        return j
    }
}

public final class BufferedPCM: @unchecked Sendable {
    public enum Result: Sendable { case accepted, overflow, closed }
    public let stream: AsyncStream<[Float]>
    private let continuation: AsyncStream<[Float]>.Continuation
    private let lock = NSLock()
    private let capacity: Int
    private var count = 0
    private var closed = false
    public init(capacity: Int = 16000 * 12) {
        self.capacity = capacity
        (stream, continuation) = AsyncStream<[Float]>.makeStream()
    }
    public func append(_ samples: [Float]) -> Result {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return .closed }
        guard samples.count <= capacity - count else {
            closed = true; continuation.finish(); return .overflow
        }
        count += samples.count
        continuation.yield(samples)
        return .accepted
    }
    public func consumed(_ samples: [Float]) {
        lock.lock(); defer { lock.unlock() }
        count = max(0, count - samples.count)
    }
    public func finish() {
        lock.lock(); defer { lock.unlock() }
        closed = true; continuation.finish()
    }
}
