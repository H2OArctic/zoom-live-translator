import Foundation

public enum TranslationNumbers {
    private static let words: [String: Int] = {
        let groups: [(Int, String)] = [
            (0, "zero ноль"), (1, "one first один одна одно первый первая первое"),
            (2, "two second два две второй вторая второе"), (3, "three third три третий третья третье"),
            (4, "four fourth четыре четвертый четвертая"), (5, "five fifth пять пятый пятая"),
            (6, "six sixth шесть шестой шестая"), (7, "seven seventh семь седьмой седьмая"),
            (8, "eight eighth восемь восьмой восьмая"), (9, "nine ninth девять девятый девятая"),
            (10, "ten tenth десять десятый десятая"), (11, "eleven eleventh одиннадцать одиннадцатый одиннадцатая"),
            (12, "twelve twelfth двенадцать двенадцатый двенадцатая"),
            (13, "thirteen thirteenth тринадцать тринадцатый тринадцатая"),
            (14, "fourteen fourteenth четырнадцать четырнадцатый четырнадцатая"),
            (15, "fifteen fifteenth пятнадцать пятнадцатый пятнадцатая"),
            (16, "sixteen sixteenth шестнадцать шестнадцатый шестнадцатая"),
            (17, "seventeen seventeenth семнадцать семнадцатый семнадцатая"),
            (18, "eighteen eighteenth восемнадцать восемнадцатый восемнадцатая"),
            (19, "nineteen nineteenth девятнадцать девятнадцатый девятнадцатая"),
            (20, "twenty twentieth двадцать двадцатый двадцатая"),
            (30, "thirty thirtieth тридцать тридцатый тридцатая"),
            (40, "forty fortieth сорок сороковой сороковая"),
            (50, "fifty fiftieth пятьдесят пятидесятый пятидесятая"),
            (60, "sixty sixtieth шестьдесят шестидесятый шестидесятая шестьдесятая"),
            (70, "seventy seventieth семьдесят семидесятый семидесятая"),
            (80, "eighty eightieth восемьдесят восьмидесятый восьмидесятая"),
            (90, "ninety ninetieth девяносто девяностый девяностая девяностых"),
            (100, "сто сотый сотая"), (200, "двести двухсотый двухсотая"),
            (300, "триста трехсотый трехсотая"), (400, "четыреста"), (500, "пятьсот"),
            (600, "шестьсот"), (700, "семьсот"), (800, "восемьсот"), (900, "девятьсот")
        ]
        var result = Dictionary(uniqueKeysWithValues: groups.flatMap { value, forms in forms.split(separator: " ").map { (String($0), value) } })
        for (value, stem) in [(1, "перв"), (2, "втор"), (4, "четверт"), (5, "пят"), (6, "шест"), (7, "седьм"), (8, "восьм"), (9, "девят"),
            (10, "десят"), (20, "двадцат"), (30, "тридцат"), (40, "сороков"), (50, "пятидесят"), (60, "шестидесят"),
            (70, "семидесят"), (80, "восьмидесят"), (90, "девяност"), (100, "сот"), (200, "двухсот"), (300, "трехсот")] {
            for ending in ["ого", "ой", "ому", "ым", "ом", "ую", "ых", "ыми"] { result[stem + ending] = value }
        }
        for word in ["третьего", "третьей", "третьему", "третьим", "третьем", "третью", "третьих", "третьими"] { result[word] = 3 }
        return result
    }()
    private static let tokens = try! NSRegularExpression(pattern: #"\d+(?:[.,]\d+)*|[\p{L}]+|[^\s\p{L}\d]"#)

    public static func russianInput(_ text: String) -> String {
        let regex = try! NSRegularExpression(pattern: #"[а-яёА-ЯЁ]+"#)
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var replacements: [(Range<String.Index>, String)] = []
        var index = 0
        while index < matches.count {
            guard let range = Range(matches[index].range, in: text),
                  var value = words[text[range].lowercased().replacingOccurrences(of: "ё", with: "е")] else { index += 1; continue }
            let start = range.lowerBound
            var end = range.upperBound
            var last = value
            var lastWord = String(text[range]).lowercased()
            index += 1
            while index < matches.count, let next = Range(matches[index].range, in: text),
                  text[end..<next.lowerBound].allSatisfy({ $0.isWhitespace }),
                  let part = words[text[next].lowercased().replacingOccurrences(of: "ё", with: "е")],
                  (last >= 100 && part < 100) || (last >= 20 && last < 100 && last.isMultiple(of: 10) && part < 10) {
                value += part; last = part; end = next.upperBound
                lastWord = String(text[next]).lowercased(); index += 1
            }
            guard value >= 10 else { continue }
            let suffix = [("ого", "-го"), ("его", "-го"), ("ому", "-му"), ("ему", "-му"), ("ыми", "-ми"), ("ими", "-ми"),
                ("ая", "-я"), ("яя", "-я"), ("ья", "-я"), ("ый", "-й"), ("ой", "-й"), ("ий", "-й"), ("ей", "-й"),
                ("ое", "-е"), ("ее", "-е"), ("ье", "-е"), ("ых", "-х"), ("их", "-х"), ("ом", "-м"), ("ем", "-м"),
                ("ым", "-м"), ("им", "-м"), ("ую", "-ю"), ("ью", "-ю")].first { lastWord.hasSuffix($0.0) }?.1 ?? ""
            replacements.append((start..<end, "\(value)\(suffix)"))
        }
        var result = text
        for (range, value) in replacements.reversed() { result.replaceSubrange(range, with: value) }
        return result
    }

    public static func values(in text: String) -> Set<String> {
        var lowered = TechnicalTranslation.spokenDecimals(text).lowercased().replacingOccurrences(of: "ё", with: "е")
        let groupedNumbers = try! NSRegularExpression(pattern: #"\b\d{1,3}(?:[ \u00a0\u202f]\d{3})+(?:[.,]\d+)?\b"#)
        for match in groupedNumbers.matches(in: lowered, range: NSRange(lowered.startIndex..., in: lowered)).reversed() {
            if let range = Range(match.range, in: lowered) {
                let value = lowered[range].filter { !$0.isWhitespace }
                lowered.replaceSubrange(range, with: value)
            }
        }
        let tokens = Self.tokens.matches(in: lowered, range: NSRange(lowered.startIndex..., in: lowered)).compactMap {
            Range($0.range, in: lowered).map { String(lowered[$0]) }
        }
        var values = Set<String>()
        var amount: Double?
        var last: Int?
        var thousands: Double = 0
        func formatted(_ value: Double) -> String { String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value).replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression) }
        func flush() {
            if let amount { values.insert(formatted(thousands + amount)) }
            else if thousands != 0 { values.insert(formatted(thousands)) }
            amount = nil; last = nil; thousands = 0
        }
        for token in tokens {
            if let value = words[token] {
                if let previous = last, let current = amount,
                   (previous >= 100 && value < 100) || (previous >= 20 && previous < 100 && previous.isMultiple(of: 10) && value < 10) {
                    amount = current + Double(value)
                } else { if amount != nil { flush() }; amount = Double(value) }
                last = value
            } else if ["million", "millions", "миллион", "миллиона", "миллионов"].contains(token) {
                thousands += (amount ?? 1) * 1_000_000; amount = nil; last = nil
            } else if ["hundred", "hundredth", "thousand", "thousands", "тысяча", "тысячи", "тысяч", "k", "к"].contains(token), let current = amount {
                if token.hasPrefix("hundred") { amount = current * 100; last = 100 }
                else { thousands += current * 1000; amount = nil; last = nil }
            } else if token.first?.isNumber == true {
                flush()
                let grouped = token.range(of: #"^\d{1,3}(?:,\d{3})+(?:\.\d+)?$"#, options: .regularExpression) != nil
                let normalized = grouped ? token.replacingOccurrences(of: ",", with: "") : token.replacingOccurrences(of: ",", with: ".")
                amount = Double(normalized)
            } else if token == "-", last != nil {
                continue
            } else { flush() }
        }
        flush()
        return values
    }
}
