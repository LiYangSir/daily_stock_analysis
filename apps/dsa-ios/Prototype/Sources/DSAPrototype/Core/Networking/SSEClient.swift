import Foundation

public struct SSEEvent: Sendable {
    public let event: String
    public let data: String
}

/// 极简 SSE 解析器（基于 URLSession.bytes）。仅供原型用，断线重连暂未实现。
public struct SSEClient {
    public init() {}

    public func stream(url: URL, headers: [String: String] = [:]) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var request = URLRequest(url: url)
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                        continuation.finish(throwing: APIError.unauthorized)
                        return
                    }

                    var event = "message"
                    var data = ""
                    for try await line in bytes.lines {
                        if line.isEmpty {
                            if !data.isEmpty {
                                continuation.yield(SSEEvent(event: event, data: data))
                            }
                            event = "message"
                            data = ""
                        } else if line.hasPrefix("event:") {
                            event = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            let part = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                            data = data.isEmpty ? part : data + "\n" + part
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
