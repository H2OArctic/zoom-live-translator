import AVFoundation
import Foundation
import Speech
import Translation

@main
struct Capabilities {
    static func print(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }

    static func main() async {
        print("Memory GB: \(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)")
        print("SpeechTranscriber: \(SpeechTranscriber.isAvailable)")
        let speech = await SpeechTranscriber.supportedLocales.map(\.identifier).sorted()
        let dictation = await DictationTranscriber.supportedLocales.map(\.identifier).sorted()
        print("Speech locales: \(speech.joined(separator: ", "))")
        print("Dictation locales: \(dictation.joined(separator: ", "))")
        print("Installed speech: \(await SpeechTranscriber.installedLocales.map(\.identifier))")
        let availability = LanguageAvailability()
        for (source, target) in [("en", "ru"), ("ru", "en")] {
            let status = await availability.status(from: .init(identifier: source), to: .init(identifier: target))
            print("Translation \(source) → \(target): \(status)")
        }
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") || $0.language.hasPrefix("ru") }
        print("Voices: \(voices.map { "\($0.name) [\($0.language)]" }.joined(separator: ", "))")
    }
}
