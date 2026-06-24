import Foundation

/// 极简 API 客户端：cookie 自动跟随，统一错误映射。
/// 自部署场景下证书可能无效（自签 / 过期 / 域名不匹配），通过 TrustAllDelegate 放行。
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
        self.session = URLSession(configuration: config,
                                   delegate: TrustAllDelegate(),
                                   delegateQueue: nil)
    }

    public func updateBaseURL(_ url: URL) {
        self.baseURL = url
    }

    public func send<T: Decodable & Sendable>(_ endpoint: Endpoint, as type: T.Type = T.self) async throws -> T {
        let request = try makeRequest(endpoint)
        let (data, response) = try await dataTask(for: request)
        try validate(response: response, data: data, url: request.url)
        do {
            return try JSONDecoder.dsa.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    public func sendVoid(_ endpoint: Endpoint) async throws {
        let request = try makeRequest(endpoint)
        let (data, response) = try await dataTask(for: request)
        try validate(response: response, data: data, url: request.url)
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
        request.setValue("DSA-iOS/0.1 (iPhone; iOS 17) Mobile/Safari", forHTTPHeaderField: "User-Agent")
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

    private func validate(response: URLResponse, data: Data, url: URL?) throws {
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
            let body = String(data: data, encoding: .utf8)?.prefix(180) ?? ""
            let path = url?.path ?? ""
            let message = "请求失败 \(http.statusCode) · \(path)" + (body.isEmpty ? "" : "\n\(body)")
            throw APIError.server(code: "http_\(http.statusCode)", message: message)
        }
    }
}

private struct ErrorEnvelope: Decodable {
    struct Detail: Decodable { let error: String; let message: String }
    let detail: Detail
}

/// 信任任意服务端证书（仅自部署场景，原型用）。
final class TrustAllDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        urlSession(session, didReceive: challenge, completionHandler: completionHandler)
    }
}

/// 共享的信任全部证书的 URLSession（供 SSE 等不走 APIClient 的地方使用）。
public enum TrustAllSession {
    public static let shared: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.timeoutIntervalForRequest = 60
        return URLSession(configuration: config, delegate: TrustAllDelegate(), delegateQueue: nil)
    }()
}
