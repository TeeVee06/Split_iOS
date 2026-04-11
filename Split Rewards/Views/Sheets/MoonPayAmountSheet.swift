import SwiftUI

struct MoonPayAmountSheet: View {
    private let minimumEstimatedUsdAmount = 20.0

    enum AmountUnit: String, CaseIterable {
        case usd = "USD"
        case sats = "Sats"
    }

    let btcUsdRate: Double?
    let isStarting: Bool
    let onStart: (_ lockedAmountSats: UInt64, _ estimatedSpendAmountCents: Int) -> Void
    let onCancel: () -> Void

    @State private var amountUnit: AmountUnit = .usd
    @State private var amountText: String = ""
    @FocusState private var amountFieldFocused: Bool

    private let appBlack = Color.splitAppBlack
    private let cardSurface = Color.splitCardSurface
    private let fieldSurface = Color.white.opacity(0.08)
    private let segmentedSurface = Color.white.opacity(0.06)

    private var lockedAmountSats: UInt64? {
        parseLockedAmountSats(for: amountUnit, inputText: amountText)
    }

    private var estimatedUsdAmount: Double? {
        guard let lockedAmountSats, let rate = btcUsdRate, rate > 0 else { return nil }
        return (Double(lockedAmountSats) / 100_000_000.0) * rate
    }

    private var estimatedSpendAmountCents: Int? {
        guard let estimatedUsdAmount else { return nil }
        let cents = Int((estimatedUsdAmount * 100.0).rounded())
        return cents > 0 ? cents : nil
    }

    private var canContinue: Bool {
        !isStarting
            && lockedAmountSats != nil
            && estimatedSpendAmountCents != nil
            && (estimatedUsdAmount ?? 0) >= minimumEstimatedUsdAmount
    }

    private var convertedValueText: String {
        guard let lockedAmountSats, let estimatedUsdAmount else {
            if amountUnit == .usd {
                return btcUsdRate == nil
                    ? "Waiting for Bitcoin price to estimate sats."
                    : "Enter a USD amount."
            }

            return btcUsdRate == nil
                ? "Enter sats. USD estimate appears when price data loads."
                : "Enter a sats amount."
        }

        switch amountUnit {
        case .usd:
            return "MoonPay will lock \(formatSats(lockedAmountSats)) sats. Estimated cost: \(formatUSDDisplay(estimatedUsdAmount))."
        case .sats:
            return "Estimated purchase value: \(formatUSDDisplay(estimatedUsdAmount)). MoonPay will lock exactly \(formatSats(lockedAmountSats)) sats."
        }
    }

    private var minimumRequirementText: String {
        guard let estimatedUsdAmount else {
            return "MoonPay requires a minimum order of \(formatUSDDisplay(minimumEstimatedUsdAmount))."
        }

        if estimatedUsdAmount < minimumEstimatedUsdAmount {
            return "Min order must be at least \(formatUSDDisplay(minimumEstimatedUsdAmount))."
        }

        return "MoonPay minimum met."
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBlack
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Enter Amount")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)

                        Text("You can enter USD or sats.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.64))
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Amount Unit", selection: $amountUnit) {
                            ForEach(AmountUnit.allCases, id: \.self) { unit in
                                Text(unit.rawValue).tag(unit)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(4)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(segmentedSurface)
                        )

                        TextField(amountUnit == .usd ? "100.00" : "100000", text: $amountText)
                            .keyboardType(amountUnit == .usd ? .decimalPad : .numberPad)
                            .focused($amountFieldFocused)
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(fieldSurface)
                            )

                        Text(convertedValueText)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white.opacity(0.66))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        summaryRow("Locked BTC amount", value: lockedAmountSats.map(formatSats) ?? "—")
                        summaryRow("Estimated USD", value: estimatedUsdAmount.map(formatUSDDisplay) ?? "—")
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(cardSurface)
                    )

                    Text("MoonPay's quote may vary slightly in fiat terms.")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.55))

                    Text(minimumRequirementText)
                        .font(.footnote.weight(.medium))
                        .foregroundColor((estimatedUsdAmount ?? 0) >= minimumEstimatedUsdAmount ? .green.opacity(0.82) : .pink.opacity(0.92))

                    Spacer()

                    VStack(spacing: 12) {
                        Button {
                            guard let lockedAmountSats, let estimatedSpendAmountCents else { return }
                            onStart(lockedAmountSats, estimatedSpendAmountCents)
                        } label: {
                            HStack {
                                Spacer()
                                if isStarting {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Continue to MoonPay")
                                        .font(.headline.weight(.semibold))
                                        .foregroundColor(.white)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(canContinue ? Color.splitBrandPink : Color.white.opacity(0.12))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canContinue)

                        Button(action: onCancel) {
                            HStack {
                                Spacer()
                                Text("Cancel")
                                    .font(.headline.weight(.medium))
                                    .foregroundColor(.white.opacity(0.78))
                                Spacer()
                            }
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(Color.white.opacity(0.07))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isStarting)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 20)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onChange(of: amountUnit) { oldUnit, newUnit in
            syncDisplayForSelectedUnit(from: oldUnit, to: newUnit)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    amountFieldFocused = false
                }
            }
        }
    }

    private func summaryRow(_ title: String, value: String) -> some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.76))

            Spacer(minLength: 16)

            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white)
        }
    }

    private func syncDisplayForSelectedUnit(from oldUnit: AmountUnit, to newUnit: AmountUnit) {
        guard oldUnit != newUnit else { return }

        if let lockedAmountSats {
            switch newUnit {
            case .usd:
                if let estimatedUsdAmount {
                    amountText = formatUSDInput(estimatedUsdAmount)
                } else {
                    amountText = ""
                }
            case .sats:
                amountText = "\(lockedAmountSats)"
            }
        } else {
            amountText = ""
        }
    }

    private func parseLockedAmountSats(for unit: AmountUnit, inputText: String) -> UInt64? {
        let cleaned = inputText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")

        switch unit {
        case .sats:
            guard let sats = UInt64(cleaned), sats > 0 else { return nil }
            return sats
        case .usd:
            guard let usd = Double(cleaned),
                  usd > 0,
                  let rate = btcUsdRate,
                  rate > 0 else {
                return nil
            }

            let satsDouble = (usd / rate) * 100_000_000.0
            guard satsDouble.isFinite, satsDouble > 0 else { return nil }
            return UInt64(max(1, Int64(satsDouble.rounded())))
        }
    }

    private func formatSats(_ sats: UInt64) -> String {
        "\(NumberFormatter.localizedString(from: NSNumber(value: sats), number: .decimal)) sats"
    }

    private func formatUSDInput(_ usd: Double) -> String {
        String(format: "%.2f", usd)
    }

    private func formatUSDDisplay(_ usd: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: usd)) ?? "$\(formatUSDInput(usd))"
    }
}
