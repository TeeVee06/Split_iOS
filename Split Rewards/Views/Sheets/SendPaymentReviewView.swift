//  SendPaymentReviewView.swift
//  Split
//
//  Step 2 of the send flow: review BTC + USD amounts and fees, then confirm.
//

import SwiftUI

struct SendPaymentReviewView: View {
    @EnvironmentObject var walletManager: WalletManager

    let preview: WalletManager.PaymentPreview
    /// Called when the user wants to exit the entire send flow
    /// and return to the main customer index view
    /// (e.g., after a successful send or tapping the X).
    let onExitFlow: () -> Void

    @State private var isSending: Bool = false
    @State private var errorMessage: String?

    // MARK: - Derived values for UI

    private var amountBTC: Double {
        Double(preview.amountSats) / 100_000_000.0
    }

    /// Implied BTC/USD rate from the preview (if we have USD + BTC).
    private var impliedBtcUsdRate: Double? {
        guard preview.amountSats > 0,
              let usd = preview.amountFiatUSD else {
            return nil
        }
        let btc = amountBTC
        guard btc > 0 else { return nil }
        return usd / btc
    }

    private var routingFeeUSD: Double? {
        guard let feeSats = preview.routingFeeSats,
              let rate = impliedBtcUsdRate else {
            return nil
        }
        let feeBTC = Double(feeSats) / 100_000_000.0
        return feeBTC * rate
    }

    private var totalBTC: Double? {
        guard preview.amountSats > 0 else { return nil }
        let feeSats = preview.routingFeeSats ?? 0
        let totalSats = preview.amountSats + feeSats
        return Double(totalSats) / 100_000_000.0
    }

    private var totalUSD: Double? {
        guard let rate = impliedBtcUsdRate,
              let totalBTC = totalBTC else { return nil }
        return totalBTC * rate
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.97)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Top bar with X and title (mirrors ReceiveInvoiceView)
                HStack {
                    Button(action: { onExitFlow() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }

                    Spacer()

                    Text("Confirm Payment")
                        .font(.headline)
                        .foregroundColor(.white)

                    Spacer()

                    Color.clear
                        .frame(width: 32, height: 32)
                }
                .padding(.top, 8)

                // Recipient
                VStack(alignment: .leading, spacing: 8) {
                    Text("To")
                        .font(.caption)
                        .foregroundColor(.gray)

                    Text(recipientTitle)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.88))

                    if let recipientSubtitle, !recipientSubtitle.isEmpty {
                        Text(recipientSubtitle)
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.88))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Main amount card
                VStack(spacing: 12) {
                    Text("Amount")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if preview.amountSats > 0 {
                        VStack(alignment: .leading, spacing: 6) {
                            if let usd = preview.amountFiatUSD {
                                Text(formatUSD(usd))
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            } else {
                                Text("\(formatBTC(amountBTC)) BTC")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            }

                            Text("\(formatBTC(amountBTC)) BTC")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Amount set in invoice")
                                .font(.subheadline)
                                .foregroundColor(.white)

                            Text("The Lightning invoice you scanned includes the amount.")
                                .font(.footnote)
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
                .background(Color.splitInputSurface)
                .cornerRadius(16)

                // Fee & total card
                VStack(spacing: 12) {
                    HStack {
                        Text("Details")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Spacer()
                    }

                    VStack(spacing: 8) {
                        // Payment row
                        HStack {
                            Text("Payment")
                                .foregroundColor(.white)
                            Spacer()
                            if let usd = preview.amountFiatUSD {
                                Text(formatUSD(usd))
                                    .foregroundColor(.white)
                            } else if preview.amountSats > 0 {
                                Text("\(formatBTC(amountBTC)) BTC")
                                    .foregroundColor(.white)
                            } else {
                                Text("—")
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                        .font(.subheadline)

                        // Fee row (USD only if possible)
                        HStack {
                            Text("Network fee")
                                .foregroundColor(.white)
                            Spacer()
                            if let feeUSD = routingFeeUSD {
                                Text(formatUSD(feeUSD))
                                    .foregroundColor(.white)
                            } else if preview.routingFeeSats != nil {
                                Text("Fee calculated on send")
                                    .foregroundColor(.white.opacity(0.7))
                            } else {
                                Text("—")
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                        .font(.subheadline)

                        Divider()
                            .background(Color.white.opacity(0.15))

                        // Total row
                        HStack {
                            Text("Total")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                if let totalUSD = totalUSD {
                                    Text(formatUSD(totalUSD))
                                        .foregroundColor(.white)
                                } else if let totalBTC = totalBTC {
                                    Text("\(formatBTC(totalBTC)) BTC")
                                        .foregroundColor(.white)
                                } else {
                                    Text("—")
                                        .foregroundColor(.white.opacity(0.7))
                                }

                                if let totalBTC = totalBTC {
                                    Text("\(formatBTC(totalBTC)) BTC")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                    }
                }
                .padding()
                .background(Color.splitInputSurfaceSecondary)
                .cornerRadius(16)

                if let error = errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()

                // Send button
                Button(action: send) {
                    HStack {
                        Spacer()
                        if isSending {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Text("Send")
                                .font(.headline)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(Color.white.opacity(isSending ? 0.3 : 1.0))
                    .foregroundColor(.black)
                    .cornerRadius(18)
                }
                .disabled(isSending)

                Text("Payments can’t be reversed. Double-check the recipient and amount before sending.")
                    .font(.footnote)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            if isSending {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - Helpers

    private var recipientName: String? {
        preview.recipientName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank
    }

    private var normalizedPaymentRequest: String {
        let trimmed = preview.paymentRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        if lower.hasPrefix("lightning:") {
            return String(trimmed.dropFirst("lightning:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmed
    }

    private var isLightningInvoice: Bool {
        let lower = normalizedPaymentRequest.lowercased()
        return lower.hasPrefix("lnbc") || lower.hasPrefix("lntb") || lower.hasPrefix("lnbcrt")
    }

    private var recipientTitle: String {
        if let recipientName {
            return recipientName
        }

        if isLightningInvoice {
            return "Lightning Invoice"
        }

        return normalizedPaymentRequest
    }

    private var recipientSubtitle: String? {
        guard recipientName != nil else { return nil }
        guard !isLightningInvoice else { return nil }
        return normalizedPaymentRequest.nilIfBlank
    }

    private func formatUSD(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "$\(String(format: "%.2f", value))"
    }

    private func formatBTC(_ btc: Double) -> String {
        String(format: "%.8f", btc)
    }

    // MARK: - Send

    private func send() {
        errorMessage = nil
        isSending = true

        Task {
            let success = await walletManager.confirmPreparedPayment(preview: preview)

            await MainActor.run {
                isSending = false

                if success {
                    // Breez has accepted the payment into its process.
                    // Exit the entire send flow and return to CustomerIndexView.
                    onExitFlow()
                } else {
                    errorMessage = walletManager.lastErrorMessage ?? "Failed to send payment."
                }
            }
        }
    }
}
