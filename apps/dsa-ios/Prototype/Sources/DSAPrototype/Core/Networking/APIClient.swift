import Foundation

/// 极简 API 客户端：cookie 自动跟随，统一错误映射。
public actor APIClient {
    public private(set) var baseURL: URL
    private let session: URLSession

    public init(baseURL: URL) {
        self.baseURL = baseURL

        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    public func updateBaseURL(_ url: URL) {
        self.baseURL = url
    }

    public func send<T: Decodable & Sendable>(_ endpoint: Endpoint, as type: T.Type = T.self) async throws -> T {
        let request = try makeRequest(endpoint)
        let (data, response) = try await dataTask(for: request)
        try validate(response: response, data: data)
        do {
            return try JSONDecoder.dsa.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    public func sendVoid(_ endpoint: Endpoint) async throws {
        let request = try makeRequest(endpoint)
        let (data, response) = try await dataTask(for: request)
        try validate(response: response, data: data)
    }

    // MARK: - Private

    private func makeRequest(_ endpoint: Endpoint) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("api/v1\(endpoint.path)"), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        if !endpoint.query.isEmpty {
            components.queryItems = endpoint.query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = endpoint.body
        return request
    }

    private func dataTask(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200...299: return
        case 401:
            throw APIError.unauthorized
        case 429:
            throw APIError.rateLimited
        default:
            if let detail = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
                throw APIError.server(code: detail.detail.error, message: detail.detail.message)
            }
            throw APIError.server(code: "http_\(http.statusCode)", message: "请求失败 (\(http.statusCode))")
        }
    }
}

private struct ErrorEnvelope: Decodable {
    struct Detail: Decodable { let error: String; let message: String }
    let detail: Detail
}
