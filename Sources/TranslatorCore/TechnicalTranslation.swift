import Foundation

public enum TechnicalTranslation {
    private static let digits = ["zero": 0, "one": 1, "two": 2, "three": 3, "four": 4,
                                 "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9]
    private static let tens = ["twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
                               "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90]
    private static let digitPattern = "zero|one|two|three|four|five|six|seven|eight|nine"

    public static func englishInput(_ text: String) -> String {
        var result = spokenDecimals(text)
        result = replace(result, pattern: #"\bfix(?:ed)?\s+(engine|sessions?)\b"#) { "FIX " + $0[1].lowercased() }
        if result.range(of: #"\bissue\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            result = replace(result, pattern: #"\bFIX engine(?=\s+(?:one|two|three|four|five|six|seven|eight|nine)\s+(?:twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety)\b)"#) { _ in "FIX engine issue" }
        }
        result = replace(result, pattern: #"\bFIX\s*(?:four\s+(two|four)|4\s+([24])|4([24]))\b"#) { parts in
            let minor = digits[parts[1].lowercased()].map(String.init) ?? (parts[2].isEmpty ? parts[3] : parts[2])
            return "FIX 4.\(minor)"
        }
        result = replace(result, pattern: #"\b(issue|tag)\s+(one|two|three|four|five|six|seven|eight|nine)\s+(twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety)(?:[ -]+(one|two|three|four|five|six|seven|eight|nine))?\b"#) { parts in
            let value = digits[parts[2].lowercased()]! * 100 + tens[parts[3].lowercased()]! + (digits[parts[4].lowercased()] ?? 0)
            return parts[1] + (parts[1].lowercased() == "issue" ? " #" : " ") + "\(value)"
        }
        result = replace(result, pattern: #"\bprod\s+(?:oh|o|zero)\s+(one|two|three|[123])\b"#) { parts in
            "PROD0" + (digits[parts[1].lowercased()].map(String.init) ?? parts[1])
        }
        return result
    }

    public static func spokenDecimals(_ text: String) -> String {
        replace(text, pattern: "\\b(\(digitPattern))\\s+point\\s+(\(digitPattern))\\b") { parts in
            "\(digits[parts[1].lowercased()]!).\(digits[parts[2].lowercased()]!)"
        }
    }

    public static func terminology(for text: String) -> String {
        let entries = [
            (#"\bFIX(?:\s+(?:engine|sessions?|protocol|version)|\s*4[. ]?[24])\b"#, "FIX engine = движок FIX; FIX session = сессия FIX. FIX is a protocol name, never исправление. FIX 4.2 and FIX 4.4 are protocol versions."),
            (#"\b(fence|fencing|failover|servers?|boxes)\b"#, "In server failover: up/down = работает/выключен; fence/fencing = изолировать сервер/изоляция сервера, never торговать."),
            (#"\bloop\s?back\b"#, "loopback = локальный адрес обратной петли, not rollback; venue = торговая площадка."),
            (#"\b(short|long|flat|flattened|reduce.only|working orders)\b"#, "Trading: long = длинная позиция; short = короткая позиция; ending up short = оказаться в короткой позиции; flat/flatten = нулевая позиция/закрыть позицию; reduce-only = только уменьшение позиции; working orders = активные ордера. A million euro long means длинная позиция на миллион евро, never debt or a loan. Always retain long/short position direction. Preserve each/per-order quantities."),
            (#"\b(hop|sequence|gap)\b"#, "hop = звено передачи данных; sequence gap = пропуск в последовательности; sequence number = порядковый номер."),
            (#"\b(margin|spot|drop copy)\b"#, "margin = маржинальная торговля; spot = спотовая торговля; drop copy = drop copy, never percentage."),
            (#"\b(WAN|LAN|NOC|SQLite|L3|IPC|PROD\d+)\b"#, "WAN, LAN, NOC, SQLite, L3, IPC and PROD server identifiers are technical names; preserve them exactly."),
            (#"\b(issue|tag)\b"#, "issue followed by a number = задача №; tag followed by a number = тег. An issue number is not a software version.")
        ]
        return entries.filter { text.range(of: $0.0, options: [.regularExpression, .caseInsensitive]) != nil }
            .map(\.1).joined(separator: " ")
    }

    private static func replace(_ text: String, pattern: String, replacement: ([String]) -> String) -> String {
        let regex = try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: text) else { continue }
            let parts = (0..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
            }
            result.replaceSubrange(range, with: replacement(parts))
        }
        return result
    }
}
