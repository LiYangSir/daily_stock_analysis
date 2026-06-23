import Foundation
import Combine

@MainActor
public final class AuthService: ObservableObject {
    @Published public private(set) var status: AuthStatus = AuthStatus(authEnabled: false, loggedIn: true, passwordSet: nil, setupState: nil)
    @Published public var baseURLString: String {
        didSet { UserDefaults.standard.set(baseURLString, forKey: Self.baseURLKey) }
    }

    public let api: APIClient

    private static let baseURLKey = "dsa.baseURL"

    public init() {
        let stored = UserDefaults.standard.string(forKey: Self.baseURLKey) ?? "https://dsa.example.com"
        self.baseURLString = stored
        self.api = APIClient(baseURL: URL(string: stored) ?? URL(string: "https://dsa.example.com")!)
    }

    public func updateBaseURL(_ string: String) async {
        baseURLString = string
        if let url = URL(string: string) {
            await api.updateBaseURL(url)
        }
    }

    public func refreshStatus() async {
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
        await refreshStatus()
    }

    public func logout() async {
        try? await api.sendVoid(Endpoint(path: "/auth/logout", method: .POST))
        await refreshStatus()
    }
}
