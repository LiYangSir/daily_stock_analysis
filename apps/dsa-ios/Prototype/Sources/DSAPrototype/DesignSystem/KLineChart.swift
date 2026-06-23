import SwiftUI
import Charts

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
        let upColor = DSColor.up(market, scheme: scheme)
        let downColor = DSColor.down(market, scheme: scheme)
        let ma5 = movingAverage(window: 5)
        let ma10 = movingAverage(window: 10)
        let ma20 = movingAverage(window: 20)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                legend("MA5", value: ma5.last?.value, color: .orange)
                legend("MA10", value: ma10.last?.value, color: .blue)
                legend("MA20", value: ma20.last?.value, color: .purple)
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
                        width: .fixed(1)
                    )
                    .foregroundStyle(isUp ? upColor : downColor)
                    RectangleMark(
                        x: x,
                        yStart: .value("o", bar.open),
                        yEnd: .value("c", bar.close),
                        width: .fixed(5)
                    )
                    .foregroundStyle(isUp ? upColor : downColor)
                }
                ForEach(Array(ma5.enumerated()), id: \.offset) { i, v in
                    LineMark(x: .value("idx", v.index), y: .value("ma5", v.value))
                        .foregroundStyle(.orange)
                        .interpolationMethod(.monotone)
                }
                ForEach(Array(ma10.enumerated()), id: \.offset) { _, v in
                    LineMark(x: .value("idx", v.index), y: .value("ma10", v.value))
                        .foregroundStyle(.blue)
                        .interpolationMethod(.monotone)
                }
                ForEach(Array(ma20.enumerated()), id: \.offset) { _, v in
                    LineMark(x: .value("idx", v.index), y: .value("ma20", v.value))
                        .foregroundStyle(.purple)
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
        let upColor = DSColor.up(market, scheme: scheme)
        let downColor = DSColor.down(market, scheme: scheme)

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
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(Color.secondary.opacity(0.15))
                    AxisValueLabel().font(.system(size: 9))
                }
            }
            .frame(height: 60)
        }
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
