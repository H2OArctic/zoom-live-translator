import Foundation

public enum TextChunks {
    public static func split(_ text: String, limit: Int) -> [String] {
        precondition(limit > 0)
        var remaining = text[...]
        var chunks: [String] = []
        while !remaining.isEmpty {
            let hardEnd = remaining.index(remaining.startIndex, offsetBy: limit, limitedBy: remaining.endIndex) ?? remaining.endIndex
            var end = hardEnd
            if hardEnd < remaining.endIndex {
                let prefix = remaining[..<hardEnd]
                if let boundary = prefix.lastIndex(where: { ".!?。！？\n".contains($0) }),
                   remaining.distance(from: remaining.startIndex, to: boundary) >= limit / 3 {
                    end = remaining.index(after: boundary)
                } else if let space = prefix.lastIndex(where: \.isWhitespace), space > remaining.startIndex {
                    end = remaining.index(after: space)
                }
            }
            let chunk = remaining[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty { chunks.append(chunk) }
            remaining = remaining[end...]
        }
        return chunks
    }
}
