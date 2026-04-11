//  RampCode.swift
//  Split Rewards
//
//
import SwiftUI
#if canImport(Charts)
import Charts
#endif

struct RampPriceCard: View {
    let priceText: String
    let onTapPrice: () -> Void
    let onRefreshPrice: () -> Void
    let onBuy: () -> Void

    private let blue = Color.splitBrandBlue
    private let pink = Color.splitBrandPink
    private let berry = Color.splitBerry

    @State private var showInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Button(action: onTapPrice) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Market")
                            .font(.caption.weight(.heavy))
                            .tracking(1.4)
                            .foregroundColor(.white.opacity(0.62))

                        HStack(spacing: 6) {
                            Text(priceText)
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .monospacedDigit()

                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white.opacity(0.92))
                        }

                        Text("Bitcoin Price")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.70))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 10) {
                    Button {
                        showInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $showInfo) {
                        ZStack {
                            LinearGradient(
                                colors: [
                                    Color.splitAppBlack,
                                    Color.splitSurface
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .ignoresSafeArea()

                            ScrollView {
                                VStack(alignment: .leading, spacing: 12) {
                                    (
                                        Text("₿")
                                            .foregroundColor(pink) +
                                        Text("itcoin Purchases")
                                            .foregroundColor(.white)
                                    )
                                    .font(.system(size: 26, weight: .bold, design: .rounded))
                                    .padding(.top, 30)
                                    .padding(.bottom, 12)

                                    Text("Rewards")
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                        .foregroundColor(.white)

                                    Text("Eligible Bitcoin purchases made through Split-supported on-ramp providers are credited in our rewards program. See program details in the Rewards Explained section for specifics.")
                                        .font(.system(size: 14, weight: .regular, design: .rounded))
                                        .foregroundColor(.white.opacity(0.88))
                                        .fixedSize(horizontal: false, vertical: true)

                                    Text("Fees")
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                        .foregroundColor(.white)

                                    Text("There are fees associated with Bitcoin purchases that go to the selected provider and the Spark network. None of those fees go to Split.")
                                        .font(.system(size: 14, weight: .regular, design: .rounded))
                                        .foregroundColor(.white.opacity(0.88))
                                        .fixedSize(horizontal: false, vertical: true)

                                    Text("We designed the rewards program to offset those fees with Bitcoin rewards as much as possible. Ideally the rewards you earn from a purchase will completely cover the cost of the fees.")
                                        .font(.system(size: 14, weight: .regular, design: .rounded))
                                        .foregroundColor(.white.opacity(0.88))
                                        .fixedSize(horizontal: false, vertical: true)

                                    Text("Delivery + timing")
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                        .foregroundColor(.white)

                                    Text("Your Bitcoin will be sent to your wallet’s onchain address. It may take between 30–60 minutes for your Bitcoin to be confirmed. Once confirmed, you can move the Bitcoin into your Split wallet via the Claim Bitcoin section.")
                                        .font(.system(size: 14, weight: .regular, design: .rounded))
                                        .foregroundColor(.white.opacity(0.88))
                                        .fixedSize(horizontal: false, vertical: true)

                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 16)
                                .padding(.bottom, 16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                    }

                    Button(action: onRefreshPrice) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Color.white.opacity(0.10))
                .frame(height: 1)

            Button(action: onBuy) {
                HStack(spacing: 6) {
                    Text("Buy")
                        .font(.callout.weight(.semibold))

                    (
                        Text("₿")
                            .font(.callout.weight(.semibold))
                        +
                        Text("itcoin")
                            .font(.callout.weight(.semibold))
                    )
                }
                .foregroundColor(.white)
                .frame(height: 46)
                .frame(width: 170)
                .background(
                    LinearGradient(
                        colors: [blue, pink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.32), lineWidth: 1)
                )
                .shadow(color: berry.opacity(0.22), radius: 14, x: 0, y: 8)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.05),
                            Color.white.opacity(0.02),
                            Color.black.opacity(0.82)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 16, x: 0, y: 8)
    }
}

@available(iOS 16.0, *)
struct BitcoinPriceChartFullscreenView: View {
    let initialRange: BitcoinChartRange
    let onClose: () -> Void

    @State private var selectedRange: BitcoinChartRange
    @State private var points: [BitcoinPricePoint] = []
    @State private var isLoading: Bool = false
    @State private var errorText: String? = nil
    @State private var selectedPoint: BitcoinPricePoint? = nil

    private let blue = Color.splitBrandBlue
    private let pink = Color.splitBrandPink
    private let berry = Color.splitBerry
    private let indigo = Color.splitIndigo
    private let surface = Color.splitSurface
    private let surfaceRaised = Color.splitSurfaceRaised
    private let appBlack = Color.splitAppBlack

    init(initialRange: BitcoinChartRange, onClose: @escaping () -> Void) {
        self.initialRange = initialRange
        self.onClose = onClose
        _selectedRange = State(initialValue: initialRange)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [appBlack, surface],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                chartBody
                    .padding(.horizontal, 16)

                rangePicker
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
            }
        }
        .task(id: selectedRange) {
            await load()
        }
        .onChange(of: selectedRange) { _, _ in
            selectedPoint = nil
        }
    }

    private var displayedPoint: BitcoinPricePoint? {
        selectedPoint ?? points.last
    }

    private var currentPriceText: String {
        guard let p = displayedPoint else { return "—" }
        return formatUSD(p.priceUSD)
    }

    private var currentPriceSubtitleText: String? {
        guard let p = displayedPoint else { return nil }

        let df = DateFormatter()
        df.locale = .current
        df.timeZone = .current

        if selectedPoint != nil {
            df.dateStyle = .medium
            df.timeStyle = .short
            return df.string(from: p.date)
        }

        switch selectedRange {
        case .day:
            df.dateStyle = .none
            df.timeStyle = .short
        case .month, .year, .yearToDate:
            df.dateStyle = .medium
            df.timeStyle = .none
        }

        return "As of \(df.string(from: p.date))"
    }

    private var percentChangeText: String {
        guard
            let first = points.first?.priceUSD,
            let shown = displayedPoint?.priceUSD,
            first != 0
        else { return "—" }

        let pct = (shown - first) / first * 100.0
        let sign = pct >= 0 ? "+" : ""
        return "\(sign)\(formatPercent(pct))"
    }

    private var percentChangeColor: Color {
        guard
            let first = points.first?.priceUSD,
            let shown = displayedPoint?.priceUSD
        else { return .white.opacity(0.75) }

        if shown > first { return .green }
        if shown < first { return .red }
        return .white.opacity(0.75)
    }

    private var header: some View {
        HStack {
            Text("Bitcoin")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Spacer()

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(10)
                    .background(surfaceRaised)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var chartBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(currentPriceText)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                HStack(spacing: 10) {
                    Text(percentChangeText)
                        .font(.callout.weight(.semibold))
                        .foregroundColor(percentChangeColor)
                        .monospacedDigit()

                    if let subtitle = currentPriceSubtitleText {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.70))
                    }
                }
            }
            .padding(.top, 2)

            if isLoading {
                HStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("Loading chart…")
                        .foregroundColor(.white.opacity(0.8))
                        .font(.callout)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 40)
                .padding(.bottom, 40)
            } else if let errorText {
                VStack(spacing: 10) {
                    Text("Couldn’t load chart")
                        .foregroundColor(.white)
                        .font(.headline)

                    Text(errorText)
                        .foregroundColor(.white.opacity(0.75))
                        .font(.footnote)
                        .multilineTextAlignment(.center)

                    Button("Retry") {
                        Task { await load() }
                    }
                    .foregroundColor(.white)
                    .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 40)
                .padding(.bottom, 40)
            } else if points.isEmpty {
                Text("No data.")
                    .foregroundColor(.white.opacity(0.75))
                    .padding(.top, 40)
                    .padding(.bottom, 40)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                chartView
                    .padding(.top, 8)
            }
        }
    }

    private var chartView: some View {
        let prices = points.map { $0.priceUSD }
        let minPrice = prices.min() ?? 0
        let maxPrice = prices.max() ?? 0
        let rawRange = maxPrice - minPrice

        let padding = rawRange > 0 ? (rawRange * 0.10) : max(1.0, maxPrice * 0.002)
        let lowerBound = minPrice - padding
        let upperBound = maxPrice + padding

        return Chart {
            ForEach(points) { p in
                LineMark(
                    x: .value("Time", p.date),
                    y: .value("Price", p.priceUSD)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [blue, pink],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }

            if let sp = selectedPoint {
                RuleMark(x: .value("Selected", sp.date))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(.white.opacity(0.35))

                PointMark(
                    x: .value("Selected", sp.date),
                    y: .value("Price", sp.priceUSD)
                )
                .symbolSize(55)
                .foregroundStyle(.white)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: lowerBound...upperBound)
        .frame(height: 260)
        .background(
            LinearGradient(
                colors: [surface, indigo.opacity(0.90)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard let plotFrame = proxy.plotFrame else { return }
                                let plotArea = geo[plotFrame]
                                let xInPlot = value.location.x - plotArea.origin.x
                                guard xInPlot >= 0, xInPlot <= plotArea.size.width else { return }

                                if let date: Date = proxy.value(atX: xInPlot) {
                                    selectedPoint = nearestPoint(to: date)
                                }
                            }
                            .onEnded { _ in
                                selectedPoint = nil
                            }
                    )
            }
        }
    }

    private func nearestPoint(to date: Date) -> BitcoinPricePoint? {
        guard !points.isEmpty else { return nil }
        return points.min { a, b in
            abs(a.date.timeIntervalSince(date)) < abs(b.date.timeIntervalSince(date))
        }
    }

    private func formatUSD(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    private func formatPercent(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return (formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)) + "%"
    }

    private var rangePicker: some View {
        HStack(spacing: 10) {
            rangeButton(.day, title: "Day")
            rangeButton(.month, title: "Month")
            rangeButton(.year, title: "Year")
            rangeButton(.yearToDate, title: "YTD")
        }
        .frame(maxWidth: .infinity)
    }

    private func rangeButton(_ range: BitcoinChartRange, title: String) -> some View {
        let isSelected = (range == selectedRange)

        return Button {
            selectedRange = range
        } label: {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    Group {
                        if isSelected {
                            LinearGradient(
                                colors: [berry, pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        } else {
                            surfaceRaised
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(isSelected ? 0.16 : 0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorText = nil
        selectedPoint = nil

        do {
            let series = try await fetchBitcoinPriceSeriesUSD(range: selectedRange)
            points = series
            isLoading = false
        } catch {
            errorText = error.localizedDescription
            isLoading = false
        }
    }
}
