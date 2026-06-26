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
        let cacheKey = ResponseCache.cacheKeyIfCacheable(
            method: endpoint.method.rawValue, path: endpoint.path, query: endpoint.query)
        do {
            let (data, response) = try await dataTask(for: request)
            try validate(response: response, data: data, url: request.url)
            // 读类 GET 成功：落盘缓存（仅 2xx 才走到这里）
            if let cacheKey { await ResponseCache.shared.write(data, for: cacheKey) }
            do {
                return try JSONDecoder.dsa.decode(T.self, from: data)
            } catch {
                throw APIError.decoding(error)
            }
        } catch {
            // 离线兜底：仅网络层失败（非取消、非 HTTP 业务错误）时，返回该 GET 的上次缓存。
            if let cacheKey, Self.isTransport(error),
               let cached = await ResponseCache.shared.read(cacheKey),
               let decoded = try? JSONDecoder.dsa.decode(T.self, from: cached) {
                return decoded
            }
            throw error
        }
    }

    /// 是否为可走离线兜底的「网络层」错误（取消与 HTTP 业务错误不算）。
    private static func isTransport(_ error: Error) -> Bool {
        if case .transport(let underlying) = error as? APIError {
            return !(underlying is CancellationError)
        }
        return false
    }

    /// 读取该 GET 的缓存并解码（首屏秒开：先渲染缓存，再由网络刷新）。
    /// 无缓存或解码失败返回 nil；不做网络请求。
    public func sendCached<T: Decodable & Sendable>(_ endpoint: Endpoint, as type: T.Type = T.self) async -> T? {
        guard let key = ResponseCache.cacheKeyIfCacheable(
            method: endpoint.method.rawValue, path: endpoint.path, query: endpoint.query),
              let cached = await ResponseCache.shared.read(key) else { return nil }
        return try? JSONDecoder.dsa.decode(T.self, from: cached)
    }

    public func sendVoid(_ endpoint: Endpoint) async throws {
        let request = try makeRequest(endpoint)
        let (data, response) = try await dataTask(for: request)
        try validate(response: response, data: data, url: request.url)
    }

    /// multipart/form-data 上传（CSV / 图片等）。fields 为普通表单字段，files 为文件部分。
    public func sendMultipart<T: Decodable & Sendable>(
        path: String,
        method: Endpoint.Method = .POST,
        query: [String: String] = [:],
        fields: [String: String] = [:],
        files: [UploadFile] = [],
        as type: T.Type = T.self
    ) async throws -> T {
        let (request, _) = try makeUploadRequest(path: path, method: method, query: query, fields: fields, files: files)
        let (data, response) = try await dataTask(for: request)
        try validate(response: response, data: data, url: request.url)
        do {
            return try JSONDecoder.dsa.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    /// multipart 上传的 fire-and-forget 版本。
    public func sendMultipartVoid(
        path: String,
        method: Endpoint.Method = .POST,
        query: [String: String] = [:],
        fields: [String: String] = [:],
        files: [UploadFile] = []
    ) async throws {
        let (request, _) = try makeUploadRequest(path: path, method: method, query: query, fields: fields, files: files)
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

    /// 构造 multipart/form-data 请求（自定义 Content-Type，不复用 makeRequest 的 application/json）。
    private func makeUploadRequest(
        path: String,
        method: Endpoint.Method,
        query: [String: String],
        fields: [String: String],
        files: [UploadFile]
    ) throws -> (URLRequest, String) {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("api/v1\(path)"), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw APIError.invalidURL }
        let boundary = "----DSA-iOS-\(UUID().uuidString)"
        let body = MultipartForm.encode(fields: fields, files: files, boundary: boundary)
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("DSA-iOS/0.1 (iPhone; iOS 17) Mobile/Safari", forHTTPHeaderField: "User-Agent")
        request.httpBody = body
        return (request, boundary)
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

/// multipart 上传的一个文件部分。
public struct UploadFile: Sendable {
    public let field: String      // 表单字段名，如 "file"
    public let filename: String   // 文件名，如 "trades.csv"
    public let mimeType: String   // 如 "text/csv"
    public let data: Data
    public init(field: String, filename: String, mimeType: String, data: Data) {
        self.field = field; self.filename = filename; self.mimeType = mimeType; self.data = data
    }
}

/// 极简 multipart/form-data body 构造器。
enum MultipartForm {
    static func encode(fields: [String: String], files: [UploadFile], boundary: String) -> Data {
        var body = Data()
        let crlf = "\r\n"
        for (name, value) in fields {
            body.appendString("--\(boundary)\(crlf)")
            body.appendString("Content-Disposition: form-data; name=\"\(name)\"\(crlf)\(crlf)")
            body.appendString("\(value)\(crlf)")
        }
        for file in files {
            body.appendString("--\(boundary)\(crlf)")
            body.appendString("Content-Disposition: form-data; name=\"\(file.field)\"; filename=\"\(file.filename)\"\(crlf)")
            body.appendString("Content-Type: \(file.mimeType)\(crlf)\(crlf)")
            body.append(file.data)
            body.appendString(crlf)
        }
        body.appendString("--\(boundary)--\(crlf)")
        return body
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        append(Data(string.utf8))
    }
}
