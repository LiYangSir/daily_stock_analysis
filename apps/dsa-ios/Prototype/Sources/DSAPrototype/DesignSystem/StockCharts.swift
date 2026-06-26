import SwiftUI
#if canImport(UIKit)
import UIKit
import DGCharts

/// 同花顺风格 K 线图组（DGCharts）：价格(K线+MA) → 成交量 → MACD 三段，
/// x 轴联动（双指缩放 / 拖动 同步），右侧价格轴自适应（不从 0 起），底部日期轴。
struct StockChartGroup: View {
    let bars: [KLineData]
    let market: Market
    let scheme: StockColorScheme
    @StateObject private var holder = ChartHolder()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                maLegend("MA5", THSColor.ma5)
                maLegend("MA10", THSColor.ma10)
                maLegend("MA20", THSColor.ma20)
            }
            .font(.system(size: 11))
            .padding(.horizontal, 4)

            PriceChartView(bars: bars, syncer: holder.syncer)
                .frame(height: 210)
            VolumeChartView(bars: bars, syncer: holder.syncer)
                .frame(height: 46)
            MACDChartView(bars: bars, syncer: holder.syncer)
                .frame(height: 60)
        }
    }

    private func maLegend(_ name: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Rectangle().fill(color).frame(width: 10, height: 2)
            Text(name).foregroundStyle(.secondary)
        }
    }
}

@MainActor
final class ChartHolder: ObservableObject {
    let syncer = ChartSyncer()
}

// MARK: - 价格图（K 线 + MA5/10/20）

struct PriceChartView: UIViewRepresentable {
    let bars: [KLineData]
    let syncer: ChartSyncer

    func makeUIView(context: Context) -> CombinedChartView {
        let chart = CombinedChartView()
        chart.delegate = syncer
        chart.legend.enabled = false
        chart.chartDescription.enabled = false
        chart.dragEnabled = true
        chart.setScaleEnabled(true)
        chart.pinchZoomEnabled = true
        chart.scaleYEnabled = false          // 仅 X 轴缩放，Y 自适应数据
        chart.autoScaleMinMaxEnabled = true  // Y 轴随可见区间动态重算
        chart.leftAxis.enabled = false
        chart.rightAxis.enabled = true       // 价格轴在右
        chart.rightAxis.labelFont = .systemFont(ofSize: 9)
        chart.rightAxis.labelTextColor = .secondaryLabel
        chart.rightAxis.setLabelCount(4, force: false)   // 限制刻度数，避免重叠
        chart.rightAxis.drawGridLinesEnabled = true
        chart.rightAxis.gridColor = UIColor.secondaryLabel.withAlphaComponent(0.12)
        chart.xAxis.labelPosition = .topInside
        chart.xAxis.enabled = false          // 日期轴由最底部 MACD 图统一显示
        chart.drawOrder = [CombinedChartView.DrawOrder.candle.rawValue,
                           CombinedChartView.DrawOrder.line.rawValue]
        chart.highlightPerDragEnabled = true // 拖动时高亮（竖线十字光标）
        chart.highlightPerTapEnabled = false
        chart.maxVisibleCount = 300
        chart.noDataText = "暂无K线数据"
        syncer.price = chart
        return chart
    }

    func updateUIView(_ chart: CombinedChartView, context: Context) {
        guard !bars.isEmpty else { chart.data = nil; chart.notifyDataSetChanged(); return }
        let data = CombinedChartData()
        data.candleData = candleData()
        data.lineData = maData()
        chart.data = data
        chart.notifyDataSetChanged()
    }

    private func candleData() -> CandleChartData {
        let entries = bars.enumerated().map { i, b in
            CandleChartDataEntry(x: Double(i), shadowH: b.high, shadowL: b.low, open: b.open, close: b.close)
        }
        let set = CandleChartDataSet(entries: entries, label: "K")
        set.increasingColor = THSUIColor.up
        set.decreasingColor = THSUIColor.down
        set.increasingFilled = true
        set.decreasingFilled = true
        set.shadowColorSameAsCandle = true
        set.neutralColor = THSUIColor.up
        set.barSpace = 0.18
        set.axisDependency = .right
        set.drawValuesEnabled = false
        set.highlightLineWidth = 1
        set.highlightColor = UIColor.label.withAlphaComponent(0.5)
        return CandleChartData(dataSet: set)
    }

    private func maData() -> LineChartData {
        let defs: [(Int, UIColor)] = [(5, THSUIColor.ma5), (10, THSUIColor.ma10), (20, THSUIColor.ma20)]
        let sets = defs.map { window, color -> LineChartDataSet in
            let entries = Self.movingAverage(bars: bars, window: window).map {
                ChartDataEntry(x: Double($0.index), y: $0.value)
            }
            let ds = LineChartDataSet(entries: entries, label: "MA\(window)")
            ds.setColor(color)
            ds.lineWidth = 1
            ds.drawCirclesEnabled = false
            ds.drawValuesEnabled = false
            ds.axisDependency = .right
            ds.highlightEnabled = false
            return ds
        }
        return LineChartData(dataSets: sets)
    }

    static func movingAverage(bars: [KLineData], window: Int) -> [(index: Int, value: Double)] {
        guard bars.count >= window else { return [] }
        var out: [(Int, Double)] = []
        for i in (window - 1)..<bars.count {
            let slice = bars[(i - window + 1)...i].map(\.close)
            out.append((i, slice.reduce(0, +) / Double(window)))
        }
        return out
    }
}

// MARK: - 成交量图

struct VolumeChartView: UIViewRepresentable {
    let bars: [KLineData]
    let syncer: ChartSyncer

    func makeUIView(context: Context) -> BarChartView {
        let chart = BarChartView()
        chart.delegate = syncer
        chart.legend.enabled = false
        chart.chartDescription.enabled = false
        chart.dragEnabled = true
        chart.setScaleEnabled(true)
        chart.pinchZoomEnabled = true
        chart.scaleYEnabled = false
        chart.leftAxis.enabled = false
        chart.rightAxis.enabled = true
        chart.rightAxis.labelFont = .systemFont(ofSize: 8)
        chart.rightAxis.labelTextColor = .secondaryLabel
        chart.rightAxis.setLabelCount(2, force: false)
        chart.rightAxis.drawGridLinesEnabled = false
        chart.xAxis.enabled = false
        chart.fitBars = true
        chart.autoScaleMinMaxEnabled = true
        chart.highlightPerTapEnabled = false
        chart.highlightPerDragEnabled = false
        syncer.volume = chart
        return chart
    }

    func updateUIView(_ chart: BarChartView, context: Context) {
        let entries = bars.enumerated().map { i, b in BarChartDataEntry(x: Double(i), y: b.volume ?? 0, data: nil) }
        let set = BarChartDataSet(entries: entries, label: "成交量")
        set.colors = bars.map { ($0.close >= $0.open) ? THSUIColor.up : THSUIColor.down }
        set.drawValuesEnabled = false
        let data = BarChartData(dataSet: set)
        data.barWidth = 0.7
        chart.data = data
        chart.rightAxis.axisMinimum = 0
        chart.notifyDataSetChanged()
    }
}

// MARK: - MACD 图（柱 + DIF/DEA 双线）

struct MACDChartView: UIViewRepresentable {
    let bars: [KLineData]
    let syncer: ChartSyncer

    func makeUIView(context: Context) -> CombinedChartView {
        let chart = CombinedChartView()
        chart.delegate = syncer
        chart.legend.enabled = false
        chart.chartDescription.enabled = false
        chart.dragEnabled = true
        chart.setScaleEnabled(true)
        chart.pinchZoomEnabled = true
        chart.scaleYEnabled = false
        chart.leftAxis.enabled = false
        chart.rightAxis.enabled = true
        chart.rightAxis.labelFont = .systemFont(ofSize: 8)
        chart.rightAxis.labelTextColor = .secondaryLabel
        chart.rightAxis.setLabelCount(3, force: false)
        chart.rightAxis.drawGridLinesEnabled = false
        chart.autoScaleMinMaxEnabled = true
        chart.xAxis.labelPosition = .bottom
        chart.xAxis.labelFont = .systemFont(ofSize: 9)
        chart.xAxis.labelTextColor = .secondaryLabel
        chart.xAxis.granularity = 1
        chart.xAxis.drawGridLinesEnabled = false
        chart.drawOrder = [CombinedChartView.DrawOrder.bar.rawValue,
                           CombinedChartView.DrawOrder.line.rawValue]
        chart.highlightPerDragEnabled = false
        syncer.macd = chart
        return chart
    }

    func updateUIView(_ chart: CombinedChartView, context: Context) {
        let macd = Self.computeMACD(bars: bars)
        let barEntries = macd.map { BarChartDataEntry(x: Double($0.index), y: $0.macd, data: nil) }
        let barSet = BarChartDataSet(entries: barEntries, label: "MACD")
        barSet.colors = macd.map { $0.macd >= 0 ? THSUIColor.up : THSUIColor.down }
        barSet.drawValuesEnabled = false

        let difSet = LineChartDataSet(entries: macd.map { ChartDataEntry(x: Double($0.index), y: $0.dif) }, label: "DIF")
        difSet.setColor(THSUIColor.ma5); difSet.lineWidth = 1; difSet.drawCirclesEnabled = false; difSet.drawValuesEnabled = false; difSet.highlightEnabled = false
        let deaSet = LineChartDataSet(entries: macd.map { ChartDataEntry(x: Double($0.index), y: $0.dea) }, label: "DEA")
        deaSet.setColor(THSUIColor.ma10); deaSet.lineWidth = 1; deaSet.drawCirclesEnabled = false; deaSet.drawValuesEnabled = false; deaSet.highlightEnabled = false

        let data = CombinedChartData()
        data.barData = BarChartData(dataSet: barSet)
        data.lineData = LineChartData(dataSets: [difSet, deaSet])
        chart.xAxis.valueFormatter = DateAxisFormatter(bars.map(\.date))
        chart.data = data
        chart.notifyDataSetChanged()
    }

    static func computeMACD(bars: [KLineData]) -> [(index: Int, dif: Double, dea: Double, macd: Double)] {
        let closes = bars.map(\.close)
        let dif = zip(ema(closes, 12), ema(closes, 26)).map(-)
        let dea = ema(dif, 9)
        guard dif.count == dea.count else { return [] }
        return (0..<dif.count).map { i in (i, dif[i], dea[i], (dif[i] - dea[i]) * 2) }
    }

    private static func ema(_ values: [Double], _ period: Int) -> [Double] {
        guard !values.isEmpty else { return [] }
        let k = 2.0 / Double(period + 1)
        var out: [Double] = [values[0]]
        for i in 1..<values.count { out.append(values[i] * k + out[i - 1] * (1 - k)) }
        return out
    }
}

// MARK: - 三图 x 轴联动

final class ChartSyncer: NSObject, ChartViewDelegate {
    weak var price: CombinedChartView?
    weak var volume: BarChartView?
    weak var macd: CombinedChartView?
    private var syncing = false

    private var charts: [BarLineChartViewBase] {
        [price, volume, macd].compactMap { $0 }
    }

    func chartTranslated(_ chartView: ChartViewBase, dX: CGFloat, dY: CGFloat) { sync(from: chartView) }
    func chartScaled(_ chartView: ChartViewBase, scaleX: CGFloat, scaleY: CGFloat) { sync(from: chartView) }

    private func sync(from source: ChartViewBase) {
        guard !syncing, let s = source as? BarLineChartViewBase else { return }
        syncing = true
        let m = s.viewPortHandler.touchMatrix
        for c in charts where c !== s {
            c.viewPortHandler.refresh(newMatrix: m, chart: c, invalidate: true)
        }
        syncing = false
    }
}

// MARK: - 同花顺 UIColor 配色 + 日期格式化

enum THSUIColor {
    static var up: UIColor { UIColor(red: 0.88, green: 0.13, blue: 0.20, alpha: 1) }
    static var down: UIColor { UIColor(red: 0.08, green: 0.58, blue: 0.30, alpha: 1) }
    static var ma5: UIColor { UIColor(red: 0.95, green: 0.62, blue: 0.10, alpha: 1) }
    static var ma10: UIColor { UIColor(red: 0.60, green: 0.27, blue: 0.85, alpha: 1) }
    static var ma20: UIColor { UIColor(red: 0.16, green: 0.56, blue: 0.92, alpha: 1) }
}

final class DateAxisFormatter: NSObject, AxisValueFormatter {
    let dates: [String]
    init(_ dates: [String]) { self.dates = dates }
    func stringForValue(_ value: Double, axis: AxisBase?) -> String {
        let idx = Int(value)
        guard dates.indices.contains(idx) else { return "" }
        return String(dates[idx].prefix(10).suffix(5))   // MM-DD
    }
}

#endif
