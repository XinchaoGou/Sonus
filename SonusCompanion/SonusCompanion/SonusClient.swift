import Foundation

enum SonusClientError: LocalizedError, Sendable {
    case invalidURL
    case connectionFailed(String)
    case timeout
    case httpError(status: Int, detail: String)
    case invalidResponse
    case emptyAudio

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Sonus server URL."
        case .connectionFailed(let url):
            return "Cannot connect to Sonus at \(url). Is `sonus serve` running?"
        case .timeout:
            return "Sonus request timed out."
        case .httpError(_, let detail):
            return detail
        case .invalidResponse:
            return "Unexpected response from Sonus server."
        case .emptyAudio:
            return "Sonus returned empty audio."
        }
    }
}

struct SonusClient: Sendable {
    var baseURL: String
    var timeoutSeconds: TimeInterval = 60

    func health() async throws {
        let data = try await get(path: "/health")
        let decoded = try JSONDecoder().decode(HealthResponse.self, from: data)
        guard decoded.status == "ok" else {
            throw SonusClientError.invalidResponse
        }
    }

    func fetchVoices() async throws -> [Voice] {
        let data = try await get(path: "/voices")
        let decoded = try JSONDecoder().decode(VoicesAPIResponse.self, from: data)
        return decoded.logical
            .map { Voice.fromLogical(id: $0.key, entry: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func fetchEngines() async throws -> [EngineStatusResponse] {
        let data = try await get(path: "/engines")
        return try JSONDecoder().decode([EngineStatusResponse].self, from: data)
    }

    func setActiveEngine(_ engineID: String) async throws -> String {
        let payload = try JSONEncoder().encode(SetActiveEngineRequest(engine: engineID))
        let (data, response) = try await put(path: "/engines/active", body: payload)
        guard let http = response as? HTTPURLResponse else {
            throw SonusClientError.invalidResponse
        }
        if http.statusCode >= 400 {
            let detail = parseErrorDetail(from: data) ?? "HTTP \(http.statusCode)"
            throw SonusClientError.httpError(status: http.statusCode, detail: detail)
        }
        let decoded = try JSONDecoder().decode(SetActiveEngineResponse.self, from: data)
        return decoded.engine
    }

    func synthesize(text: String, voice: String, speed: Double, format: String = "wav") async throws -> Data {
        let body = TTSRequest(text: text, voice: voice, speed: speed, format: format)
        let encoder = JSONEncoder()
        let payload = try encoder.encode(body)
        let (data, response) = try await post(path: "/tts", body: payload)

        guard let http = response as? HTTPURLResponse else {
            throw SonusClientError.invalidResponse
        }

        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""

        if http.statusCode >= 400 {
            let detail = parseErrorDetail(from: data) ?? "HTTP \(http.statusCode)"
            throw SonusClientError.httpError(status: http.statusCode, detail: detail)
        }

        if contentType.contains("application/json") {
            let detail = parseErrorDetail(from: data) ?? "Unknown API error"
            throw SonusClientError.httpError(status: http.statusCode, detail: detail)
        }

        guard !data.isEmpty else {
            throw SonusClientError.emptyAudio
        }

        if !(contentType.contains("audio/") || contentType.contains("application/octet-stream")) {
            throw SonusClientError.invalidResponse
        }

        return data
    }

    /// Chunked PCM stream from POST /tts/stream (16-bit mono LE @ 24 kHz).
    func synthesizeStream(text: String, voice: String, speed: Double) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines) + "/tts/stream") else {
                        throw SonusClientError.invalidURL
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.timeoutInterval = timeoutSeconds
                    request.httpBody = try JSONEncoder().encode(
                        TTSStreamRequest(text: text, voice: voice, speed: speed)
                    )

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw SonusClientError.invalidResponse
                    }

                    let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""

                    if http.statusCode >= 400 || contentType.contains("application/json") {
                        var errorData = Data()
                        errorData.reserveCapacity(512)
                        for try await byte in bytes {
                            errorData.append(byte)
                        }
                        let detail = parseErrorDetail(from: errorData) ?? "HTTP \(http.statusCode)"
                        throw SonusClientError.httpError(status: http.statusCode, detail: detail)
                    }

                    var buffer = Data()
                    buffer.reserveCapacity(8192)
                    var totalBytes = 0

                    for try await byte in bytes {
                        buffer.append(byte)
                        if buffer.count >= 8192 {
                            totalBytes += buffer.count
                            continuation.yield(buffer)
                            buffer = Data()
                            buffer.reserveCapacity(8192)
                        }
                    }

                    if !buffer.isEmpty {
                        totalBytes += buffer.count
                        continuation.yield(buffer)
                    }

                    if totalBytes == 0 {
                        throw SonusClientError.emptyAudio
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func get(path: String) async throws -> Data {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines) + path) else {
            throw SonusClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeoutSeconds

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                throw SonusClientError.httpError(status: status, detail: parseErrorDetail(from: data) ?? "HTTP \(status)")
            }
            return data
        } catch let error as SonusClientError {
            throw error
        } catch let error as URLError {
            throw mapURLError(error)
        } catch {
            throw SonusClientError.connectionFailed(baseURL)
        }
    }

    private func post(path: String, body: Data) async throws -> (Data, URLResponse) {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines) + path) else {
            throw SonusClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeoutSeconds

        do {
            return try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            throw mapURLError(error)
        } catch {
            throw SonusClientError.connectionFailed(baseURL)
        }
    }

    private func put(path: String, body: Data) async throws -> (Data, URLResponse) {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines) + path) else {
            throw SonusClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeoutSeconds

        do {
            return try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            throw mapURLError(error)
        } catch {
            throw SonusClientError.connectionFailed(baseURL)
        }
    }

    private func mapURLError(_ error: URLError) -> SonusClientError {
        switch error.code {
        case .timedOut:
            return .timeout
        case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .cannotFindHost:
            return .connectionFailed(baseURL)
        default:
            return .connectionFailed(baseURL)
        }
    }

    private func parseErrorDetail(from data: Data) -> String? {
        if let decoded = try? JSONDecoder().decode(APIErrorResponse.self, from: data), let detail = decoded.detail {
            return detail
        }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let detail = object["detail"] as? String {
            return detail
        }
        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return text
        }
        return nil
    }
}
