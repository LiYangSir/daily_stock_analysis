import Foundation

public enum APIError: LocalizedError, Sendable {
    case invalidURL
    case unauthorized
    case rateLimited
    case server(code: String, message: String)
    case decoding(Error)
    case transport(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "URL 无效"
        case .unauthorized: return "未登录或会话已过期"
        case .rateLimited: return "请求过于频繁，请稍后再试"
        case .server(_, let message): return message
        case .decoding(let error):
            if let de = error as? DecodingError {
                return "解析失败：\(de.shortDescription)"
            }
            return "返回数据解析失败"
        case .transport(let error): return error.localizedDescription
        }
    }
}

private extension DecodingError {
    var shortDescription: String {
        switch self {
        case .typeMismatch(_, let ctx),
             .valueNotFound(_, let ctx),
             .keyNotFound(_, let ctx),
             .dataCorrupted(let ctx):
            let path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
            return "\(path.isEmpty ? "<root>" : path) · \(ctx.debugDescription)"
        @unknown default:
            return "\(self)"
        }
    }
}

public struct Endpoint: Sendable {
    public enum Method: String, Sendable { case GET, POST, PUT, PATCH, DELETE }

    public let path: String
    public let method: Method
    public let query: [String: String]
    public let body: Data?

    public init(path: String, method: Method = .GET, query: [String: String] = [:], body: Data? = nil) {
        self.path = path
        self.method = method
        self.query = query
        self.body = body
    }

    public static func get(_ path: String, query: [String: String] = [:]) -> Endpoint {
        Endpoint(path: path, method: .GET, query: query)
    }

    public static func post<T: Encodable>(_ path: String, body: T) throws -> Endpoint {
        let data = try JSONEncoder.dsa.encode(body)
        return Endpoint(path: path, method: .POST, body: data)
    }
}

public extension JSONDecoder {
    static let dsa: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
}

public extension JSONEncoder {
    static let dsa: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()
}
