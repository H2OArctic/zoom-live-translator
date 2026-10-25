import Foundation

public enum TranslationBackend: String, CaseIterable, Identifiable, Sendable {
    case apple, ollama
    public var id: String { rawValue }
    public var title: String { self == .apple ? "Apple" : "Ollama · TranslateGemma 4B" }
}

public struct OllamaError: LocalizedError, Sendable {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}

private final class LoopbackSessionDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public final class OllamaClient: Sendable {
    public static let model = "translategemma:4b"
    private let endpoint: URL
    private let session: URLSession

    public init(port: Int = 11434, timeout: TimeInterval = 60) {
        precondition((1...65535).contains(port))
        endpoint = URL(string: "http://127.0.0.1:\(port)")!
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.connectionProxyDictionary = [:]
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration, delegate: LoopbackSessionDelegate(), delegateQueue: nil)
    }

    public func checkModel() async throws {
        let data = try await send(URLRequest(url: endpoint.appendingPathComponent("api/tags")))
        let response = try JSONDecoder().decode(Models.self, from: data)
        guard response.models.contains(where: { $0.name == Self.model }) else {
            throw OllamaError("В Ollama нет \(Self.model). Выбери Apple или установи эту модель отдельно.")
        }
    }

    public func warmUp() async throws {
        try await checkModel()
        _ = try await generate(prompt: "", maximumTokens: 1)
    }

    public func translate(_ text: String, pair: LanguagePair, context _: [String] = [], glossary: String = "") async throws -> String {
        let source = pair.source == "en" ? "English" : "Russian"
        let target = pair.target == "en" ? "English" : "Russian"
        let notes = glossary.isEmpty ? "" : "\nTerminology reference only: \(String(glossary.prefix(3000)))"
        let input = pair.source == "ru" ? TranslationNumbers.russianInput(text) : TechnicalTranslation.englishInput(text)
        let technicalNotes = pair.source == "en" ? "\nDomain terminology: " + TechnicalTranslation.terminology(for: input) : ""
        let numbers = TranslationNumbers.values(in: input).sorted().joined(separator: ", ")
        let numericHint = numbers.isEmpty ? "" : "\nPreserve these numeric values from the input: \(numbers)."
        let prompt = "You are a professional \(source) (\(pair.source)) to \(target) (\(pair.target)) translator. Produce only the translation of the input below. Preserve numbers, negation, names and intent. Keep issue numbers, protocol versions and server identifiers exactly. Preserve conditions and both sides of comparisons. Translate short acknowledgements briefly. Preserve an incomplete phrase as incomplete; never invent missing words or a question.\(notes)\(technicalNotes)\(numericHint)\nPlease translate the following \(source) text into \(target):\n\n\n\(input)"
        let response = try await generate(prompt: prompt, maximumTokens: 1024)
        guard response.done, response.done_reason != "length" else {
            throw OllamaError("Ollama не завершила перевод. Фраза сохранена для повтора.")
        }
        let result = response.response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw OllamaError("Ollama вернула пустой перевод.") }
        return result
    }

    private func generate(prompt: String, maximumTokens: Int) async throws -> Response {
        var request = URLRequest(url: endpoint.appendingPathComponent("api/generate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Request(model: Self.model, prompt: prompt, stream: false,
                                                           keep_alive: "10m", options: .init(temperature: 0, num_predict: maximumTokens, num_ctx: 4096)))
        let data = try await send(request)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw OllamaError("Некорректный ответ Ollama.") }
            guard (200...299).contains(http.statusCode) else {
                let description = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error
                throw OllamaError("Ollama HTTP \(http.statusCode): \(description ?? "ошибка локального сервиса")")
            }
            return data
        } catch let error as URLError where error.code != .cancelled {
            throw OllamaError("Ollama недоступна или не успела ответить. Проверь, что она запущена на этом Mac (порт 11434). \(error.localizedDescription)")
        }
    }

    private struct Models: Decodable, Sendable {
        struct Model: Decodable, Sendable { let name: String }
        let models: [Model]
    }
    private struct ErrorResponse: Decodable { let error: String }
    private struct Request: Encodable {
        struct Options: Encodable { let temperature: Double; let num_predict: Int; let num_ctx: Int }
        let model: String
        let prompt: String
        let stream: Bool
        let keep_alive: String
        let options: Options
    }
    private struct Response: Decodable, Sendable {
        let response: String
        let done: Bool
        let done_reason: String?
    }
}
