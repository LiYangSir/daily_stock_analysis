import SwiftUI

public struct LoginView: View {
    @EnvironmentObject var auth: AuthService
    @EnvironmentObject var env: AppEnvironment
    @State private var password = ""
    @State private var confirm = ""
    @State private var isFirstSetup = false
    @State private var error: String?
    @State private var loading = false
    @State private var showAdvanced = false
    @FocusState private var focused: Field?

    enum Field: Hashable { case password, confirm, baseURL }

    public init() {}

    public var body: some View {
        ZStack {
            backgroundLayer

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // 顶部品牌：占用很小，距离顶部 SafeArea 仅 8pt
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DSA")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("股票智能分析系统")
                            .font(.footnote).foregroundStyle(.white.opacity(0.65))
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 28)

                    // 主标题
                    Text(isFirstSetup ? "首次设置" : "登录")
                        .font(.title.bold())
                    Text(isFirstSetup ? "为这个私有部署设置访问密码" : "私有部署，请输入访问密码")
                        .font(.footnote).foregroundStyle(.white.opacity(0.6))
                        .padding(.top, 4)
                        .padding(.bottom, 18)

                    // 密码（最重要，最先）
                    secureFieldRow("密码", placeholder: "至少 6 位",
                                   text: $password, focus: .password)
                    if isFirstSetup {
                        secureFieldRow("确认密码", placeholder: "再次输入",
                                       text: $confirm, focus: .confirm)
                    }

                    // BASE_URL 默认折叠（避免被误以为是密码框，且解决"删不掉"——其实是 placeholder 没显示）
                    DisclosureGroup(isExpanded: $showAdvanced) {
                        plainFieldRow("服务器地址", placeholder: "https://example.com",
                                      text: $auth.baseURLString, focus: .baseURL)
                            .padding(.top, 8)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "server.rack").font(.footnote)
                            Text("服务器：\(displayedBaseURL)")
                                .font(.footnote)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .foregroundStyle(.white.opacity(0.7))
                    }
                    .tint(.white.opacity(0.85))
                    .padding(.top, 4)

                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.red).padding(.top, 8)
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
                        .background(canSubmit ? DSColor.accent : DSColor.accent.opacity(0.4),
                                    in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                    }
                    .disabled(!canSubmit)
                    .padding(.top, 18)

                    HStack {
                        Button(isFirstSetup ? "已有密码？登录" : "首次部署？设置密码") {
                            isFirstSetup.toggle(); error = nil
                        }
                        .font(.footnote).foregroundStyle(.white.opacity(0.6))
                        Spacer()
                    }
                    .padding(.top, 14)
                    .padding(.bottom, 30)
                }
                .padding(.horizontal, 28)
                .foregroundStyle(.white)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.dark)
        .task {
            await auth.refreshStatus()
            isFirstSetup = (auth.status.setupState == "no_password")
        }
    }

    private var canSubmit: Bool {
        guard !password.isEmpty else { return false }
        if isFirstSetup { return !confirm.isEmpty && password == confirm }
        return true
    }

    private var displayedBaseURL: String {
        let s = auth.baseURLString.trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? "未设置" : s
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

    private func secureFieldRow(_ label: String, placeholder: String,
                                 text: Binding<String>, focus: Field) -> some View {
        fieldContainer(label) {
            SecureField(placeholder, text: text, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.35)))
                .focused($focused, equals: focus)
                .submitLabel(.next)
                .font(.system(size: 17))
                .foregroundStyle(.white)
                .tint(DSColor.accent)
        }
    }

    private func plainFieldRow(_ label: String, placeholder: String,
                               text: Binding<String>, focus: Field) -> some View {
        fieldContainer(label) {
            HStack(spacing: 8) {
                TextField(placeholder, text: text,
                          prompt: Text(placeholder).foregroundStyle(.white.opacity(0.35)))
                    .focused($focused, equals: focus)
                    .autocorrectionDisabled()
                    
                    
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
                    .tint(DSColor.accent)
                if !text.wrappedValue.isEmpty {
                    Button {
                        text.wrappedValue = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func fieldContainer<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 11)).tracking(0.5).foregroundStyle(.white.opacity(0.6))
            content()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.15), lineWidth: 0.5))
        .padding(.bottom, 8)
        .contentShape(Rectangle())
    }

    private func submit() async {
        error = nil
        loading = true
        defer { loading = false }
        var url = auth.baseURLString.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty else {
            self.error = "请先设置服务器地址（展开下方「服务器」）"
            return
        }
        // 去掉尾部斜杠
        while url.hasSuffix("/") { url.removeLast() }
        await auth.updateBaseURL(url)
        do {
            try await auth.login(password: password, confirm: isFirstSetup ? confirm : nil)
        } catch {
            // 展示完整错误（含 URL / 底层原因）
            let detail: String
            if let apiErr = error as? APIError {
                detail = apiErr.errorDescription ?? "\(error)"
            } else {
                detail = "\(error)"
            }
            self.error = detail
        }
    }
}
