import Foundation
import Testing
@testable import TranslatorCore

@Test func journalRetainsMoreThanVisibleHistoryAndEscapesNewlines() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let journal = try SessionJournal(directory: directory)
    for index in 0..<150 {
        journal.record("recognition_final", channel: "incoming", data: ["original": "Привет, мир!\nСтрока \(index)"])
    }
    try await journal.close()
    let lines = try String(contentsOf: journal.fileURL, encoding: .utf8).split(separator: "\n")
    #expect(lines.count == 150)
    for (index, line) in lines.enumerated() {
        let entry = try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        #expect(entry["sequence"] as? Int == index + 1)
        let fields = try #require(entry["data"] as? [String: String])
        #expect(fields["original"] == "Привет, мир!\nСтрока \(index)")
    }
}

@Test func exportFlushesQueuedWritesAndLeavesLiveJournalOpen() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let journal = try SessionJournal(directory: directory)
    let exported = directory.appendingPathComponent("export.jsonl")
    for index in 0..<120 { journal.record("translation_completed", data: ["translated": "Translation \(index)"]) }
    try await journal.export(to: exported)
    journal.record("capture_stopped")
    try await journal.close()
    let snapshot = try String(contentsOf: exported, encoding: .utf8).split(separator: "\n")
    let original = try String(contentsOf: journal.fileURL, encoding: .utf8).split(separator: "\n")
    #expect(snapshot.count == 120)
    #expect(original.count == 121)
    #expect(journal.fileURL != exported)
}
