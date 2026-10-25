import AVFoundation
import Foundation
import Speech

@main
struct IngressProbe {
    static func main() async {
        guard let native = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2),
              let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true) else { exit(1) }
        let (audio, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let (levels, levelContinuation) = AsyncStream<Double>.makeStream()
        let (errors, errorContinuation) = AsyncStream<String>.makeStream()
        let ingress = AudioIngress(format: target, continuation: continuation,
                                   onLevel: { levelContinuation.yield($0) },
                                   onError: { errorContinuation.yield($0) })
        for _ in 0..<10 {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: native, frameCapacity: 4800),
                  let channels = buffer.floatChannelData else { exit(1) }
            buffer.frameLength = 4800
            for frame in 0..<4800 {
                let sample = Float(sin(Double(frame) * 2 * .pi * 440 / 48000)) * 0.2
                channels[0][frame] = sample
                channels[1][frame] = sample
            }
            ingress.append(buffer)
        }
        ingress.finish()
        levelContinuation.finish()
        errorContinuation.finish()
        var frames = 0
        var peak: Float = 0
        for await input in audio {
            let buffer = input.buffer
            guard buffer.format.sampleRate == 16000, buffer.format.channelCount == 1,
                  let samples = buffer.int16ChannelData?[0] else { exit(1) }
            frames += Int(buffer.frameLength)
            for index in 0..<Int(buffer.frameLength) { peak = max(peak, abs(Float(samples[index]) / 32768)) }
        }
        var level = 0.0
        for await value in levels { level = max(level, value) }
        var messages: [String] = []
        for await message in errors { messages.append(message) }
        print("48kHz stereo → 16kHz mono: frames=\(frames), peak=\(peak), meter=\(level), errors=\(messages)")
        guard (15000...16500).contains(frames), peak > 0.1, level > 0, messages.isEmpty else { exit(1) }
    }
}
