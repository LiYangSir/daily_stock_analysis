import SwiftUI

public struct LoginView: View {
    @EnvironmentObject var auth: AuthService
    @EnvironmentObject var env: AppEnvironment
    @State private var password = ""
    @State private var confirm = ""
    @State private var isFirstSetup = false
    @State private var error: String?
    @State private var loading = false

    public init() {}

    public var body: some View {
        ZStack {
            backgroundLayer
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                Text("DSA")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                Text("股票智能分析系统")
                    .font(.callout).foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 4)
                Spacer()

                Text(isFirstSetup ? "首次设置" : "登录")
                    .font(.title2.bold())
                Text(isFirstSetup ? "为这个私有部署设置访问密码" : "私有部署，请输入访问密码")
                    .font(.footnote).foregroundStyle(.white.opacity(0.6))
                    .padding(.bottom, 18)

                glassField("密码", text: $password, secure: true)
                if isFirstSetup {
                    glassField("确认密码", text: $confirm, secure: true)
                }
                glassField("服务器地址", text: $auth.baseURLString)
                    .padding(.top, 6)

                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red).padding(.top, 6)
                }

                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        if loading { ProgressView().tint(.white) }
                        Text(isFirstSetup ? "设置并登录" : "登录")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(DSColor.accent, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
                }
                .padding(.top, 22)

                HStack {
                    Button(isFirstSetup ? "已有密码？登录" : "首次部署？设置密码") {
                        isFirstSetup.toggle(); error = nil
                    }
                    .font(.footnote).foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Button("跳过 · 使用 Mock 数据") {
                        env.useMockData = true
                    }
                    .font(.footnote).foregroundStyle(.white.opacity(0.6))
                }
                .padding(.top, 14)
                .padding(.bottom, 60)
            }
            .padding(.horizontal, 28)
            .foregroundStyle(.white)
        }
        .preferredColorScheme(.dark)
        .task {
            await auth.refreshStatus()
            isFirstSetup = (auth.status.setupState == "no_password")
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 28/255, green: 22/255, blue: 16/255), .black],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [DSColor.accent.opacity(0.35), .clear],
                           center: .init(x: 0.3, y: 0.2), startRadius: 0, endRadius: 320)
            RadialGradient(colors: [Color.blue.opacity(0.25), .clear],
                           center: .init(x: 0.7, y: 0.85), startRadius: 0, endRadius: 360)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func glassField(_ label: String, text: Binding<String>, secure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 11)).tracking(0.5).foregroundStyle(.white.opacity(0.6))
            Group {
                if secure { SecureField("", text: text) }
                else {
                    let field = TextField("", text: text).autocorrectionDisabled()
                    #if os(iOS)
                    field.textInputAutocapitalization(.never)
                    #else
                    field
                    #endif
                }
            }
            .font(.system(size: 17))
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.15), lineWidth: 0.5))
        .padding(.bottom, 8)
    }

    private func submit() async {
        error = nil
        loading = true
        defer { loading = false }
        if !env.auth.baseURLString.isEmpty,
           let url = URL(string: env.auth.baseURLString) {
            await env.auth.api.updateBaseURL(url)
        }
        do {
            try await auth.login(password: password, confirm: isFirstSetup ? confirm : nil)
            env.useMockData = false
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
