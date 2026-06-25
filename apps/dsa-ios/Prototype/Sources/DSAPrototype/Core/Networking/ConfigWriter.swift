import Foundation

/// 统一的 `/system/config` key-value 写入辅助。
///
/// 后端大部分设置（调度开关、通知渠道、LLM 通道、运行时模型等）都通过
/// `PUT /system/config` 以 `{key, value}` 条目形式写入，并带 `config_version`
/// 乐观锁 + `mask_token`（敏感值未改动时回传占位，后端自动 skip）。
/// 这里封装「取最新版本 → PUT → 409 冲突自动重取重试一次」的通用流程，
/// 供所有设置类写操作复用（替代各自内联的 GET+PUT 样板）。
public enum ConfigWriter {
    public static func update(
        api: APIClient,
        items: [(key: String, value: String)],
        reloadNow: Bool = true
    ) async throws -> SystemConfigUpdateResponse {
        struct Item: Encodable { let key: String; let value: String }
        struct Body: Encodable {
            let configVersion: String
            let maskToken: String
            let reloadNow: Bool
            let items: [Item]
        }

        var attempt = 0
        while true {
            attempt += 1
            let cfg: SystemConfigResponse = try await api.send(
                .get("/system/config", query: ["include_schema": "false"]))
            let body = Body(
                configVersion: cfg.configVersion ?? "",
                maskToken: cfg.maskToken ?? "******",
                reloadNow: reloadNow,
                items: items.map { Item(key: $0.key, value: $0.value) })
            do {
                return try await api.send(Endpoint(
                    path: "/system/config", method: .PUT,
                    body: try JSONEncoder.dsa.encode(body)))
            } catch APIError.server(let code, _) where code == "config_version_conflict" && attempt < 2 {
                // config_version 冲突：重新取最新版本后重试一次
                continue
            }
        }
    }
}
