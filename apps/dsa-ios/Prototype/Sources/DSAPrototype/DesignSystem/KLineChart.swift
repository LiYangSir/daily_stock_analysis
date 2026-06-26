import SwiftUI
import Charts

/// 同花顺风格配色：红涨绿跌 + MA 橙黄/紫/蓝。仅图表内使用，不影响全局涨跌语义色。
enum THSColor {
    static let up = Color(red: 0.88, green: 0.13, blue: 0.20)    // 红
    static let down = Color(red: 0.08, green: 0.58, blue: 0.30)  // 绿
    static let ma5 = Color(red: 0.95, green: 0.62, blue: 0.10)   // 橙黄
    static let ma10 = Color(red: 0.60, green: 0.27, blue: 0.85)  // 紫
    static let ma20 = Color(red: 0.16, green: 0.56, blue: 0.92)  // 蓝
}

/// K 线 + MA5/10/20 主图（Swift Charts）。原型版本仅日线。
public struct KLineChart: View {
    let bars: [KLineData]
    let market: Market
    let scheme: StockColorScheme

    public init(bars: [KLineData], market: Market, scheme: StockColorScheme) {
        self.bars = bars
        self.market = market
        self.scheme = scheme
    }

    public var body: some View {
        let upColor = THSColor.up
        let downColor = THSColor.down
        let ma5 = movingAverage(window: 5)
        let ma10 = movingAverage(window: 10)
        let ma20 = movingAverage(window: 20)
        // 自适应粗细：K 线数量多时收窄，避免重叠；MA 线统一 1pt 细线。
        let bodyW = max(2, min(6, 280.0 / Double(max(bars.count, 1))))
        let wickW = max(1, bodyW * 0.4)
        let thin = StrokeStyle(lineWidth: 1)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                legend("MA5", value: ma5.last?.value, color: THSColor.ma5)
                legend("MA10", value: ma10.last?.value, color: THSColor.ma10)
                legend("MA20", value: ma20.last?.value, color: THSColor.ma20)
            }
            .font(.system(size: 11))
            .padding(.horizontal, 4)

            Chart {
                ForEach(Array(bars.enumerated()), id: \.offset) { index, bar in
                    let x = PlottableValue.value("idx", index)
                    let isUp = bar.close >= bar.open
                    RectangleMark(
                        x: x,
                        yStart: .value("low", bar.low),
                        yEnd: .value("high", bar.high),
                        width: .fixed(wickW)
                    )
                    .foregroundStyle(isUp ? upColor : downColor)
                    RectangleMark(
                        x: x,
                        yStart: .value("o", bar.open),
                        yEnd: .value("c", bar.close),
                        width: .fixed(bodyW)
                    )
                    .foregroundStyle(isUp ? upColor : downColor)
                }
                ForEach(Array(ma5.enumerated()), id: \.offset) { _, v in
                    LineMark(x: .value("idx", v.index), y: .value("ma5", v.value))
                        .foregroundStyle(THSColor.ma5).lineStyle(thin)
                        .interpolationMethod(.monotone)
                }
                ForEach(Array(ma10.enumerated()), id: \.offset) { _, v in
                    LineMark(x: .value("idx", v.index), y: .value("ma10", v.value))
                        .foregroundStyle(THSColor.ma10).lineStyle(thin)
                        .interpolationMethod(.monotone)
                }
                ForEach(Array(ma20.enumerated()), id: \.offset) { _, v in
                    LineMark(x: .value("idx", v.index), y: .value("ma20", v.value))
                        .foregroundStyle(THSColor.ma20).lineStyle(thin)
                        .interpolationMethod(.monotone)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(Color.secondary.opacity(0.18))
                    AxisValueLabel().font(.system(size: 9))
                }
            }
            .frame(height: 180)
        }
    }

    @ViewBuilder
    private func legend(_ name: String, value: Double?, color: Color) -> some View {
        HStack(spacing: 4) {
            Rectangle().fill(color).frame(width: 8, height: 2)
            Text(name).foregroundStyle(.secondary)
            if let v = value {
                Text(String(format: "%.2f", v)).foregroundStyle(.primary).fontWeight(.medium).monospacedDigit()
            }
        }
    }

    private struct MAPoint { let index: Int; let value: Double }

    private func movingAverage(window: Int) -> [MAPoint] {
        guard bars.count >= window else { return [] }
        var result: [MAPoint] = []
        for i in (window - 1)..<bars.count {
            let slice = bars[(i - window + 1)...i].map(\.close)
            result.append(MAPoint(index: i, value: slice.reduce(0, +) / Double(window)))
        }
        return result
    }
}

/// 成交量副图（红绿柱，按 close≥open 着色）。对齐同花顺：价格 → 成交量 → MACD 三段。
public struct VolumeChart: View {
    let bars: [KLineData]
    let market: Market
    let scheme: StockColorScheme

    public init(bars: [KLineData], market: Market, scheme: StockColorScheme) {
        self.bars = bars
        self.market = market
        self.scheme = scheme
    }

    public var body: some View {
        let upColor = THSColor.up
        let downColor = THSColor.down
        Chart {
            ForEach(Array(bars.enumerated()), id: \.offset) { index, bar in
                BarMark(x: .value("idx", index), y: .value("vol", bar.volume ?? 0), width: .fixed(5))
                    .foregroundStyle((bar.close >= bar.open) ? upColor.opacity(0.55) : downColor.opacity(0.55))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 2)) { _ in
                AxisGridLine().foregroundStyle(Color.secondary.opacity(0.12))
                AxisValueLabel().font(.system(size: 8))
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 4)
    }
}

/// MACD 副图（柱 + DIF/DEA 双线）。
public struct MACDChart: View {
    let bars: [KLineData]
    let market: Market
    let scheme: StockColorScheme

    public init(bars: [KLineData], market: Market, scheme: StockColorScheme) {
        self.bars = bars
        self.market = market
        self.scheme = scheme
    }

    public var body: some View {
        let macd = computeMACD()
        let upColor = THSColor.up
        let downColor = THSColor.down

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text("DIF \(format(macd.last?.dif))").foregroundStyle(.secondary)
                Text("DEA \(format(macd.last?.dea))").foregroundStyle(.secondary)
                Text("MACD \(format(macd.last?.macd))").fontWeight(.medium)
            }
            .font(.system(size: 11)).monospacedDigit()
            .padding(.horizontal, 4)

            Chart {
                ForEach(Array(macd.enumerated()), id: \.offset) { _, p in
                    BarMark(x: .value("idx", p.index), y: .value("macd", p.macd), width: .fixed(2))
                        .foregroundStyle(p.macd >= 0 ? upColor : downColor)
                }
                ForEach(Array(macd.enumerated()), id: \.offset) { _, p in
                    LineMark(x: .value("idx", p.index), y: .value("dif", p.dif))
                        .foregroundStyle(.orange)
                }
                ForEach(Array(macd.enumerated()), id: \.offset) { _, p in
                    LineMark(x: .value("idx", p.index), y: .value("dea", p.dea))
                        .foregroundStyle(.blue)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(Color.secondary.opacity(0.12))
                    if let idx = value.as(Int.self), bars.indices.contains(idx) {
                        AxisValueLabel(Self.shortDate(bars[idx].date))
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(Color.secondary.opacity(0.15))
                    AxisValueLabel().font(.system(size: 9))
                }
            }
            .frame(height: 60)
        }
    }

    /// "2024-01-01" -> "01-01"（X 轴日期刻度用）。
    private static func shortDate(_ s: String) -> String {
        String(s.prefix(10).suffix(5))
    }

    private func format(_ v: Double?) -> String {
        guard let v else { return "—" }
        return (v >= 0 ? "+" : "") + String(format: "%.2f", v)
    }

    private struct MACDPoint { let index: Int; let dif: Double; let dea: Double; let macd: Double }

    private func computeMACD(short: Int = 12, long: Int = 26, signal: Int = 9) -> [MACDPoint] {
        guard bars.count > long else { return [] }
        let closes = bars.map(\.close)
        let emaShort = ema(values: closes, period: short)
        let emaLong = ema(values: closes, period: long)
        let dif = zip(emaShort, emaLong).map(-)
        let dea = ema(values: dif, period: signal)
        var result: [MACDPoint] = []
        for i in 0..<dif.count {
            result.append(MACDPoint(index: i, dif: dif[i], dea: dea[i], macd: (dif[i] - dea[i]) * 2))
        }
        return result
    }

    private func ema(values: [Double], period: Int) -> [Double] {
        guard !values.isEmpty else { return [] }
        let k = 2.0 / Double(period + 1)
        var out: [Double] = [values[0]]
        for i in 1..<values.count {
            out.append(values[i] * k + out[i - 1] * (1 - k))
        }
        return out
    }
}
