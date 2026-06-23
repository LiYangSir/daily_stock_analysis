# DSA iOS Prototype

Swift Package + SwiftUI 原型，1:1 映射 Web 端能力到 iPhone 原生 App。

## 状态

最短闭环：登录 → 行情主页 → 报告详情。其他 Tab（分析 / 助手 / 组合）目前为占位页。

## 用法

1. 在 Xcode 16+ 中：File → Open，选择 `apps/dsa-ios/Prototype`，Xcode 会识别为 Swift Package
2. 选择 `DSAPrototype` scheme + iPhone 16 Pro 模拟器，Run
3. 启动后默认使用 Mock 数据；切换到真实后端：
   - 进「我的」→ 修改 baseURL（如 `https://dsa.example.com`）
   - 退出登录后重新输入服务端密码

## 目录

```
Sources/DSAPrototype/
├── App/                  入口、AppEnvironment、RootView、TabBar 路由
├── Core/
│   ├── Networking/       APIClient · Endpoint · APIError · SSEClient
│   ├── Models/           Codable 模型（AnalysisReport / TaskStatus / StockQuote / KLineData）
│   ├── Auth/             AuthService + Keychain
│   └── Mock/             MockData（不连服务端时使用）
├── DesignSystem/         GlassButton / ModuleCard / PriceCell / ChangeChip / KLineChart…
└── Features/
    ├── Login/
    ├── Markets/
    ├── ReportDetail/
    ├── Analysis/         占位
    ├── Chat/             占位
    ├── Portfolio/        占位
    └── Profile/          设置主页
```

## 后续

- 21 屏视觉稿见 `../../../docs/assets/ios-mockup/index.html`
- 设计与 API 映射见 `../../../docs/ios-app-design.md`
- 真实接入 SSE / 抽屉 / 各 Tab 完整功能将在后续迭代补上
