import Foundation

public final class SessionJournal: @unchecked Sendable {
    public let fileURL: URL
    private let sessionID = UUID()
    private let queue = DispatchQueue(label: "translator.session-journal", qos: .utility)
    private let onError: @Sendable (String) -> Void
    private var handle: FileHandle?
    private var sequence = 0
    private var failure: (any Error)?
    private var isClosed = false

    public init(directory: URL, onError: @escaping @Sendable (String) -> Void = { _ in }) throws {
        self.onError = onError
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        let filename = "session-\(formatter.string(from: Date()))-\(sessionID.uuidString.prefix(8)).jsonl"
        fileURL = directory.appendingPathComponent(filename)
        guard FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        handle = try FileHandle(forWritingTo: fileURL)
    }

    public func record(_ event: String, channel: String? = nil, jobID: UUID? = nil, data: [String: String] = [:]) {
        let timestamp = Date().ISO8601Format(.init(includingFractionalSeconds: true))
        queue.async { [self] in
            guard !isClosed, failure == nil, let handle else { return }
            do {
                sequence += 1
                let entry = Entry(schemaVersion: 1, sessionID: sessionID, sequence: sequence,
                                  timestamp: timestamp, event: event, channel: channel, jobID: jobID, data: data)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                var line = try encoder.encode(entry)
                line.append(0x0a)
                try handle.write(contentsOf: line)
            } catch {
                failure = error
                onError(error.localizedDescription)
            }
        }
    }

    public func export(to destination: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            queue.async { [self] in
                do {
                    if let failure { throw failure }
                    try handle?.synchronize()
                    if destination.standardizedFileURL != fileURL.standardizedFileURL {
                        let snapshot = try Data(contentsOf: fileURL, options: .mappedIfSafe)
                        try snapshot.write(to: destination, options: .atomic)
                    }
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    public func close() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            queue.async { [self] in
                do {
                    defer { isClosed = true; handle = nil }
                    try handle?.synchronize()
                    try handle?.close()
                    if let failure { throw failure }
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private struct Entry: Codable, Sendable {
        let schemaVersion: Int
        let sessionID: UUID
        let sequence: Int
        let timestamp: String
        let event: String
        let channel: String?
        let jobID: UUID?
        let data: [String: String]
    }
}
