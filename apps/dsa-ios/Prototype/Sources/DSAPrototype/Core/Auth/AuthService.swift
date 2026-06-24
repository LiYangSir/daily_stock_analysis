import Foundation
import Combine

@MainActor
public final class AuthService: ObservableObject {
    @Published public private(set) var status: AuthStatus = AuthStatus(authEnabled: true, loggedIn: false, passwordSet: nil, setupState: nil)
    @Published public var baseURLString: String {
        didSet { UserDefaults.standard.set(baseURLString, forKey: Self.baseURLKey) }
    }

    public let api: APIClient

    private static let baseURLKey = "dsa.baseURL"

    public init() {
        let stored = UserDefaults.standard.string(forKey: Self.baseURLKey) ?? ""
        self.baseURLString = stored
        let fallback = URL(string: "https://example.invalid")!
        self.api = APIClient(baseURL: URL(string: stored) ?? fallback)
    }

    public func updateBaseURL(_ string: String) async {
        baseURLString = string
        if let url = URL(string: string) {
            await api.updateBaseURL(url)
        }
    }

    public func refreshStatus() async {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              ["http", "https"].contains(url.scheme?.lowercased())
        else { return }
        do {
            let s: AuthStatus = try await api.send(.get("/auth/status"))
            self.status = s
        } catch {
            // 网络问题保持原状
        }
    }

    public func login(password: String, confirm: String? = nil) async throws {
        struct Body: Encodable { let password: String; let passwordConfirm: String? }
        let ep = try Endpoint.post("/auth/login", body: Body(password: password, passwordConfirm: confirm))
        try await api.sendVoid(ep)
        // 登录成功（HTTP 2xx），cookie 已设，立即标记已登录，触发 UI 切换
        self.status = AuthStatus(authEnabled: true, loggedIn: true,
                                 passwordSet: true, setupState: status.setupState)
        // 后台刷新一次完整 status（不阻塞 UI）
        Task { await refreshStatus() }
    }

    public func logout() async {
        try? await api.sendVoid(Endpoint(path: "/auth/logout", method: .POST))
        await refreshStatus()
    }
}
