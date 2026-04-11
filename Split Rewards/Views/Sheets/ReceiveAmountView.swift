//  ReceiveAmountView.swift
//  Split
//
//  Enter an amount in USD, see the BTC amount, and generate a Lightning invoice.
//
import SwiftUI
import UIKit

struct ReceiveAmountView: View {
    @EnvironmentObject var walletManager: WalletManager
    @Environment(\.dismiss) private var dismiss

    @State private var usdAmountText: String = ""
    @State private var btcAmountText: String = ""
    @State private var isGenerating: Bool = false
    @State private var errorMessage: String?
    @State private var invoiceInfo: ReceiveInvoiceInfo?
    @State private var showInvoiceSheet: Bool = false

    // ✅ Description the user can enter (included in BOLT11 invoice)
    @State private var descriptionText: String = ""

    // Track which field user is editing so we only convert in that direction
    @FocusState private var focusedField: Field?
    @State private var isProgrammaticUpdate: Bool = false

    private enum Field {
        case usd, btc, description
    }

    /// Simple helper used only on the receive side UI.
    struct ReceiveInvoiceInfo {
        let invoice: String
        let amountUsd: Double
        let amountBtc: Double
    }

    // MARK: - Derived values

    private var usdAmount: Double? {
        Double(cleanNumeric(usdAmountText))
    }

    private var btcAmount: Double? {
        Double(cleanNumeric(btcAmountText))
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.opacity(0.97)
                .ignoresSafeArea()
                .onTapGesture { dismissKeyboard() }

            VStack(spacing: 24) {
                // Top bar
                HStack {
                    Button(action: {
                        dismissKeyboard()
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }

                    Spacer()

                    Text("Request BTC")
                        .font(.headline)
                        .foregroundColor(.white)

                    Spacer()

                    Color.clear
                        .frame(width: 32, height: 32)
                }
                .padding(.top, 8)

                // Amount entry + BTC display
                VStack(alignment: .leading, spacing: 16) {
                    Text("Amount in USD")
                        .font(.caption)
                        .foregroundColor(.gray)

                    HStack(spacing: 8) {
                        Text("$")
                            .font(.title2)
                            .foregroundColor(.white)

                        TextField("0.00", text: $usdAmountText)
                            .keyboardType(.decimalPad)
                            .font(.title2)
                            .foregroundColor(.white)
                            .focused($focusedField, equals: .usd)
                            .onChange(of: usdAmountText) {
                                guard focusedField == .usd else { return }
                                guard !isProgrammaticUpdate else { return }
                                Task { await updateBtcFromUsd() }
                            }
                    }
                    .padding()
                    .background(Color.splitInputSurface)
                    .cornerRadius(14)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("BTC amount")
                            .font(.caption)
                            .foregroundColor(.gray)

                        TextField("0.00000000", text: $btcAmountText)
                            .keyboardType(.decimalPad)
                            .font(.body)
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.splitInputSurface)
                            .cornerRadius(14)
                            .focused($focusedField, equals: .btc)
                            .onChange(of: btcAmountText) {
                                guard focusedField == .btc else { return }
                                guard !isProgrammaticUpdate else { return }
                                Task { await updateUsdFromBtc() }
                            }

                        Text("BTC amount is estimated from USD using the current BTC/USD rate.")
                            .font(.footnote)
                            .foregroundColor(.gray)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(10)
                            .background(Color.splitInputSurfaceSecondary)
                            .cornerRadius(14)

                        if let error = errorMessage {
                            Text(error)
                                .font(.footnote)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.leading)
                        }
                    }

                    // ✅ Optional invoice description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description (optional)")
                            .font(.caption)
                            .foregroundColor(.gray)

                        TextField("Optional", text: $descriptionText, axis: .vertical)
                            .lineLimit(1...3)
                            .textInputAutocapitalization(.sentences)
                            .disableAutocorrection(false)
                            .font(.body)
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.splitInputSurface)
                            .cornerRadius(14)
                            .focused($focusedField, equals: .description)
                            .submitLabel(.done)
                            .onSubmit { dismissKeyboard() }
                            .onChange(of: descriptionText) {
                                // Soft limit to keep invoices and UI tidy
                                if descriptionText.count > 80 {
                                    descriptionText = String(descriptionText.prefix(80))
                                }
                            }

                        Text("Keep it short. This text is embedded in the invoice and may be visible to the sender.")
                            .font(.footnote)
                            .foregroundColor(.gray)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(10)
                            .background(Color.splitInputSurfaceSecondary)
                            .cornerRadius(14)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Spacer()

                // Confirm button + helper text
                VStack(spacing: 8) {
                    Button(action: generateInvoice) {
                        HStack {
                            Spacer()
                            if isGenerating {
                                ProgressView()
                                    .tint(.black)
                            } else {
                                Text("Confirm")
                                    .font(.headline)
                            }
                            Spacer()
                        }
                        .padding()
                        .background(Color.white.opacity(isGenerating ? 0.3 : 1.0))
                        .foregroundColor(.black)
                        .cornerRadius(18)
                    }
                    .disabled(!canGenerateInvoice)

                    Text("After confirming, you'll see a QR code and Lightning invoice you can share with the payer.")
                        .font(.footnote)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }
            }

            if isGenerating {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { } // swallow taps while generating
            }
        }
        .fullScreenCover(isPresented: $showInvoiceSheet, onDismiss: {
            invoiceInfo = nil
        }) {
            if let info = invoiceInfo {
                ReceiveInvoiceView(
                    info: info,
                    onExitFlow: {
                        showInvoiceSheet = false
                        dismiss()
                    }
                )
            } else {
                Text("No invoice available.")
                    .padding()
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - Helpers

    private var canGenerateInvoice: Bool {
        guard let usd = usdAmount, usd > 0 else { return false }
        guard let btc = btcAmount, btc > 0 else { return false }
        return !isGenerating
    }

    /// Normalizes numeric entry by removing commas/spaces.
    private func cleanNumeric(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func updateBtcFromUsd() async {
        guard let usd = usdAmount, usd > 0 else {
            isProgrammaticUpdate = true
            btcAmountText = ""
            isProgrammaticUpdate = false
            return
        }

        if let btc = await walletManager.convertUsdToBtc(usdAmount: usd) {
            isProgrammaticUpdate = true
            btcAmountText = String(format: "%.8f", btc)
            isProgrammaticUpdate = false

            if let error = errorMessage,
               error.contains("rate") || error.contains("BTC") {
                errorMessage = nil
            }
        } else {
            isProgrammaticUpdate = true
            btcAmountText = ""
            isProgrammaticUpdate = false
            errorMessage = "Unable to load the current BTC rate. Please try again."
        }
    }

    /// Uses the same rate source as USD→BTC by inverting convertUsdToBtc(1.0).
    @MainActor
    private func updateUsdFromBtc() async {
        guard let btc = btcAmount, btc > 0 else {
            isProgrammaticUpdate = true
            usdAmountText = ""
            isProgrammaticUpdate = false
            return
        }

        // Get BTC-per-USD at current rate (usd=1). Then invert to USD-per-BTC.
        guard let btcPerUsd = await walletManager.convertUsdToBtc(usdAmount: 1.0),
              btcPerUsd > 0 else {
            errorMessage = "Unable to load the current BTC rate. Please try again."
            return
        }

        let usd = btc / btcPerUsd

        isProgrammaticUpdate = true
        usdAmountText = String(format: "%.2f", usd)
        isProgrammaticUpdate = false

        if let error = errorMessage,
           error.contains("rate") || error.contains("BTC") {
            errorMessage = nil
        }
    }

    private func dismissKeyboard() {
        focusedField = nil
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func generateInvoice() {
        errorMessage = nil
        dismissKeyboard()

        guard let usd = usdAmount, usd > 0 else {
            errorMessage = "Enter a valid USD amount."
            return
        }

        guard let btc = btcAmount, btc > 0 else {
            errorMessage = "Enter a valid BTC amount."
            return
        }

        let sats = UInt64((btc * 100_000_000.0).rounded())
        isGenerating = true

        Task {
            let description = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty ? "Split payment" : descriptionText

            if let invoice = await walletManager.generateBolt11Invoice(description: description, amountSats: sats) {
                await MainActor.run {
                    self.invoiceInfo = ReceiveInvoiceInfo(invoice: invoice, amountUsd: usd, amountBtc: btc)
                    self.isGenerating = false
                    self.showInvoiceSheet = true
                }
            } else {
                await MainActor.run {
                    self.isGenerating = false
                    self.errorMessage = walletManager.lastErrorMessage ?? "Failed to generate invoice."
                }
            }
        }
    }
}


