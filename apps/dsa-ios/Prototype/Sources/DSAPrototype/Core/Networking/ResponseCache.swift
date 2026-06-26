import Foundation

/// 极简磁盘响应缓存：按 cache key 存原始响应 Data。
/// 用途：离线兜底——网络层失败时返回该 GET 的上次成功响应，而不是直接报错。
/// 后续可扩展为 cache-first（首屏秒开：先渲染缓存再后台刷新）。
public actor ResponseCache {
    public static let shared = ResponseCache()

    private let dir: URL

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.dir = caches.appendingPathComponent("DSAResponseCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func fileURL(for key: String) -> URL {
        dir.appendingPathComponent(Self.hash(key)).appendingPathExtension("json")
    }

    public func read(_ key: String) -> Data? {
        try? Data(contentsOf: fileURL(for: key))
    }

    public func write(_ data: Data, for key: String) {
        try? data.write(to: fileURL(for: key), options: .atomic)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// 仅幂等 GET 且非敏感、非实时性强的读类接口参与缓存；POST/PUT/DELETE 一律不缓存。
    public static func cacheKeyIfCacheable(method: String, path: String, query: [String: String]) -> String? {
        guard method == "GET" else { return nil }
        // 排除：系统配置（含敏感/掩码）、认证、用量、任务/会话流等不宜缓存或实时性强的
        let exclude = ["/system/config", "/auth", "/usage", "/analysis/tasks", "/agent/chat"]
        if exclude.contains(where: { path.contains($0) }) { return nil }
        var k = path
        let sortedQuery = query.sorted { $0.key < $1.key }
        if !sortedQuery.isEmpty {
            k += "?" + sortedQuery.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        }
        return k
    }

    /// 稳定非加密哈希（FNV-1a），用作缓存文件名。
    private static func hash(_ s: String) -> String {
        var h: UInt64 = 14695981039346656037
        for byte in s.utf8 {
            h ^= UInt64(byte)
            h &*= 1099511628211
        }
        return String(h, radix: 16)
    }
}
