import AVFoundation
import Foundation
import Testing
@testable import TranslatorCore

@Test func audioRecordingCopiesReusedBuffersAndKeepsPacketTiming() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("incoming.caf")
    let recorder = try SessionAudioRecorder(fileURL: url)
    let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: false))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800))
    buffer.frameLength = 4800
    for channel in 0..<2 { for i in 0..<4800 { buffer.floatChannelData![channel][i] = channel == 0 ? 0.25 : -0.5 } }
    recorder.append(buffer, receivedAt: Date(timeIntervalSince1970: 100), presentationSeconds: 12.5)
    for channel in 0..<2 { for i in 0..<4800 { buffer.floatChannelData![channel][i] = 0 } }
    recorder.append(buffer, receivedAt: Date(timeIntervalSince1970: 100.1), presentationSeconds: 12.6)
    await recorder.finish()
    recorder.append(buffer)
    await recorder.finish()
    let file = try AVAudioFile(forReading: url)
    #expect(file.length == 9600)
    #expect(file.fileFormat.sampleRate == 48000)
    #expect(file.fileFormat.channelCount == 2)
    let read = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 9600))
    try file.read(into: read)
    #expect(read.floatChannelData![0][0] == 0.25)
    #expect(read.floatChannelData![1][0] == -0.5)
    #expect(read.floatChannelData![0][4800] == 0)
    let events = try String(contentsOf: recorder.indexURL, encoding: .utf8).split(separator: "\n").map {
        try JSONDecoder().decode([String: String].self, from: Data($0.utf8))
    }
    let packets = events.filter { $0["event"] == "packet" }
    #expect(packets.count == 2)
    #expect(packets[0]["startFrame"] == "0")
    #expect(packets[1]["startFrame"] == "4800")
    #expect(packets[0]["presentationSeconds"] == "12.5")
    #expect(events.last?["status"] == "complete")
    let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
    #expect(permissions?.intValue == 0o600)
}

@Test func recordingOverflowIsExplicitAndDoesNotQueueUnboundedAudio() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let recorder = try SessionAudioRecorder(fileURL: directory.appendingPathComponent("incoming.caf"), capacity: 1)
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160))
    buffer.frameLength = 160
    recorder.append(buffer)
    recorder.append(buffer)
    await recorder.finish()
    #expect(!FileManager.default.fileExists(atPath: recorder.fileURL.path))
    let data = try String(contentsOf: recorder.indexURL, encoding: .utf8)
    #expect(data.contains("incomplete"))
    #expect(!data.contains("packet"))
}

@Test func recordingRejectsFormatChangesWithoutMixingSampleRates() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let recorder = try SessionAudioRecorder(fileURL: directory.appendingPathComponent("incoming.caf"))
    for rate in [16000.0, 48000.0] {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160))
        buffer.frameLength = 160
        buffer.floatChannelData![0].initialize(repeating: 0, count: 160)
        recorder.append(buffer)
    }
    await recorder.finish()
    let file = try AVAudioFile(forReading: recorder.fileURL)
    #expect(file.length == 160)
    #expect(file.fileFormat.sampleRate == 16000)
    #expect(try String(contentsOf: recorder.indexURL, encoding: .utf8).contains("incomplete"))
}

@Test func recordingWriteFailureIsRetainedWithoutATextJournal() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("incoming.caf", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    let recorder = try SessionAudioRecorder(fileURL: url)
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160))
    buffer.frameLength = 160
    buffer.floatChannelData![0].initialize(repeating: 0, count: 160)
    recorder.append(buffer)
    await recorder.finish()
    let events = try String(contentsOf: recorder.indexURL, encoding: .utf8)
    #expect(events.contains("failed"))
    #expect(events.contains("incomplete"))
}
