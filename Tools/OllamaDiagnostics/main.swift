import Foundation
import TranslatorCore

@main
struct OllamaDiagnostics {
    static func main() async {
        let arguments = CommandLine.arguments
        let port = arguments.dropFirst().first.flatMap(Int.init) ?? 11434
        let timeout = arguments.dropFirst(2).first.flatMap(Double.init) ?? 60
        let client = OllamaClient(port: port, timeout: timeout)
        do {
            try await client.checkModel()
            if arguments.contains("--regressions") {
                let samples = ["Да", "И", "Значит,", "В тесте.", "строка шестьдесятая.", "271-й и двести вторая,",
                    "в списке есть двести третий пример.", "нагрузка составляет триста процентов."]
                for text in samples {
                    let start = Date()
                    let result = try await client.translate(text, pair: .russianToEnglish,
                        context: ["Где находится пример журнала?", "Проверим это на тестовом компьютере."],
                        glossary: TranslationQuality.defaultGlossary)
                    let row = ["original": text, "translated": result, "seconds": String(Date().timeIntervalSince(start)),
                        "warnings": TranslationQuality.warnings(original: text, translated: result, pair: .russianToEnglish).joined(separator: "; ")]
                    print(String(decoding: try JSONEncoder().encode(row), as: UTF8.self))
                }
                return
            }
            if arguments.contains("--quality") || arguments.contains("--meeting-quality") {
                let meetingSamples: [(String, [String])] = [
                    ("In this example, fence the failed server before bringing the standby server up.", []),
                    ("The sample endpoint uses loopback, not an external venue.", []),
                    ("The simulated position must not cross zero and become short.", []),
                    ("The example account is two million euro long, with two reduce-only orders for six hundred thousand each.", []),
                    ("Include the working orders when checking the example position.", []),
                    ("Check the sample service issue and fixed engine issue three forty.", []),
                    ("The example gateway supports FIX four two, but does not support FIX four four.", []),
                    ("Alice is testing issue one twenty three in the sample FIX engine.", []),
                    ("Write the example SQLite record on a separate thread to avoid blocking the notification.", []),
                    ("A WAN failure between test site A and test site B must prevent automatic failover.", []),
                    ("Record the received and sent sequence numbers for each hop in the example.", []),
                    ("Persist the sample execution events in order so a simulated crash does not lose them.", [])
                ]
                let samples: [(String, [String])] = arguments.contains("--meeting-quality") ? meetingSamples : [
                    ("Bob reviewed two example PRs.", []),
                    ("Alice, is the sample ready?", []),
                    ("The example gateway has not been configured yet.", []),
                    ("daylight saving time.", ["This is a synthetic example about changing a clock."]),
                    ("Not during the startup timer.", ["This synthetic test checks service initialization."]),
                    ("The example development branch has no new commits.", []),
                    ("Return 12 rejected execution reports within 5 seconds in the test.", []),
                    ("This example uses GitHub Actions, not Ansible.", [])
                ]
                for (text, history) in samples {
                    let start = Date()
                    let result = try await client.translate(text, pair: .englishToRussian, context: history, glossary: TranslationQuality.defaultGlossary)
                    let warnings = TranslationQuality.warnings(original: text, translated: result, pair: .englishToRussian)
                    let data: [String: String] = ["original": text, "translated": result, "seconds": String(Date().timeIntervalSince(start)), "warnings": warnings.joined(separator: "; ")]
                    let line = try JSONEncoder().encode(data)
                    print(String(decoding: line, as: UTF8.self))
                }
                return
            }
            for (text, pair) in [("Please send me the updated schedule before the meeting.", LanguagePair.englishToRussian),
                                 ("Давай сначала проверим звук, а потом начнём встречу.", LanguagePair.russianToEnglish)] {
                let started = Date()
                let translated = try await client.translate(text, pair: pair)
                print("\(pair.title) [\(String(format: "%.2f", Date().timeIntervalSince(started))) s]: \(translated)")
            }
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }
}
