//
//  SendPaymentFlowView.swift
//  Split Rewards
//
//

import SwiftUI
import Foundation
import UIKit

struct SendPaymentFlowView: View {
    enum StartMode {
        case scan
        case entry(prefilledRecipientInput: String)
    }

    @EnvironmentObject var walletManager: WalletManager
    @Environment(\.dismiss) private var dismiss

    let startMode: StartMode
    let prefilledLnurlComment: String?
    let onExitFlow: (() -> Void)?

    @State private var stage: Stage
    @State private var recipientInput: String
    @State private var normalizedRequest: String
    @State private var amountText: String = ""
    @State private var presetAmountSats: UInt64? = nil
    @State private var isAmountLocked = false
    @State private var amountUnit: AmountUnit = .usd
    @State private var isPreparing = false
    @State private var statusMessage: String?
    @State private var paymentPreview: WalletManager.PaymentPreview?
    @State private var scannedContactPayload: SplitContactPayload?
    @State private var shouldReturnToEntryAfterScan = false

    @FocusState private var focusedField: Field?

    private enum Stage: Equatable {
        case scan
        case entry
        case review
    }

    private enum Field {
        case recipient
        case amount
    }

    private enum AmountUnit: String, CaseIterable {
        case usd = "USD"
        case btc = "BTC"
    }

    init(
        startMode: StartMode,
        prefilledLnurlComment: String? = nil,
        onExitFlow: (() -> Void)? = nil
    ) {
        self.startMode = startMode
        self.prefilledLnurlComment = prefilledLnurlComment
        self.onExitFlow = onExitFlow

        switch startMode {
        case .scan:
            _stage = State(initialValue: .scan)
            _recipientInput = State(initialValue: "")
            _normalizedRequest = State(initialValue: "")
        case .entry(let prefilledRecipientInput):
            _stage = State(initialValue: .entry)
            _recipientInput = State(initialValue: prefilledRecipientInput)
            _normalizedRequest = State(initialValue: prefilledRecipientInput)
        }
    }

    var body: some View {
        Group {
            switch stage {
            case .scan:
                scanStage
            case .entry:
                entryStage
            case .review:
                reviewStage
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            if stage == .entry {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissKeyboard() }
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .fullScreenCover(item: $scannedContactPayload) { payload in
            NavigationStack {
                CreateContactView(
                    paymentIdentifier: payload.lightningAddress,
                    prefilledName: payload.suggestedName,
                    onSaved: {
                        scannedContactPayload = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            exitFlow()
                        }
                    }
                )
            }
            .environmentObject(walletManager)
        }
        .onChange(of: amountUnit) { _, _ in
            guard stage == .entry else { return }

            if !isAmountLocked {
                amountText = ""
            } else {
                syncLockedAmountDisplay()
            }
        }
        .task {
            guard stage == .entry,
                  !recipientInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            updateNormalizedRequest(from: recipientInput)
        }
    }

    private var scanStage: some View {
        ZStack {
            Color.black.opacity(0.97)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                HStack {
                    Button(action: handleScanClose) {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.black.opacity(0.9))
                            .clipShape(Circle())
                    }

                    Spacer()

                    Text("Send")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.9))

                    Spacer()

                    Color.clear
                        .frame(width: 36, height: 36)
                }
                .padding(.top, 8)
                .padding(.horizontal, 20)

                VStack(spacing: 8) {
                    Text("Scan a QR code")
                        .font(.title2.bold())
                        .foregroundColor(.white)

                    Text("We’ll open a payment or contact flow from a scanned QR code or pasted request.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }

                ZStack {
                    QRCodeScannerView(onCodeScanned: handleScannedCode)
                        .clipShape(RoundedRectangle(cornerRadius: 20))

                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)

                    VStack(spacing: 12) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 40))
                            .foregroundColor(.white.opacity(0.9))

                        Text("Align the QR code inside the frame")
                            .foregroundColor(.white)
                            .font(.subheadline)

                        Text("Scan a payment QR or Split contact QR.")
                            .font(.footnote)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                    .padding()
                    .background(Color.black.opacity(0.25))
                    .cornerRadius(20)
                }
                .aspectRatio(1, contentMode: .fit)

                Button(action: pasteFromClipboard) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.headline)
                        Text("Paste from clipboard")
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.splitFieldSurface)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                }

                if let status = statusMessage, !status.isEmpty {
                    Text(status)
                        .font(.footnote)
                        .foregroundColor(status.lowercased().contains("failed") ? .red : .gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            if isPreparing {
                preparationOverlay
            }
        }
    }

    private var entryStage: some View {
        ZStack {
            Color.black.opacity(0.97)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismissKeyboard() }

            VStack(spacing: 14) {
                HStack {
                    Button(action: { exitFlow() }) {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.black.opacity(0.9))
                            .clipShape(Circle())
                    }

                    Spacer()

                    Text("Send")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.9))

                    Spacer()

                    Button(action: openScannerFromEntry) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.splitFieldSurface)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Scan QR")
                }
                .padding(.top, 10)
                .padding(.horizontal, 20)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        recipientSection
                            .padding(.top, 10)

                        amountSection

                        continueButton

                        if let status = statusMessage, !status.isEmpty {
                            Text(status)
                                .font(.footnote)
                                .foregroundColor(status.lowercased().contains("failed") ? .red : .gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                                .padding(.top, 2)
                        }

                        Spacer(minLength: 18)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
            }

            if isPreparing {
                preparationOverlay
            }
        }
    }

    @ViewBuilder
    private var reviewStage: some View {
        if let paymentPreview {
            SendPaymentReviewView(
                preview: paymentPreview,
                onExitFlow: { completeAndExitFlow() }
            )
            .environmentObject(walletManager)
        } else {
            ZStack {
                Color.black.opacity(0.97)
                    .ignoresSafeArea()

                Text("No payment details available.")
                    .foregroundColor(.white)
                    .padding()
            }
        }
    }

    private var preparationOverlay: some View {
        Color.black.opacity(0.6)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.white)
                    Text("Loading payment details…")
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
                .padding(24)
                .background(Color.black.opacity(0.8))
                .cornerRadius(16)
            }
    }

    private var recipientSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recipient")
                .font(.headline)
                .foregroundColor(.white.opacity(0.9))

            ZStack(alignment: .topLeading) {
                if recipientInput.isEmpty {
                    Text("Lightning address, LNURL, invoice, or BTC address")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.35))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }

                TextEditor(text: $recipientInput)
                    .focused($focusedField, equals: .recipient)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.asciiCapable)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(minHeight: 110, maxHeight: 180)
                    .onChange(of: recipientInput) { _, newValue in
                        updateNormalizedRequest(from: newValue)
                    }
            }
            .background(Color.splitFieldSurface)
            .cornerRadius(14)
        }
    }

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Amount")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.9))

                Spacer()

                if isAmountLocked {
                    Text("Locked")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
            }

            ZStack(alignment: .leading) {
                if amountText.isEmpty {
                    Text(amountPlaceholder)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.35))
                        .padding(.horizontal, 16)
                }

                TextField("", text: $amountText)
                    .focused($focusedField, equals: .amount)
                    .keyboardType(.decimalPad)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(14)
            }
            .background(Color.splitFieldSurface)
            .cornerRadius(14)
            .disabled(isAmountLocked)

            amountUnitToggle
                .padding(.top, 2)

            if focusedField == .amount || focusedField == .recipient {
                HStack {
                    Spacer()

                    Button("Done") {
                        dismissKeyboard()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.10))
                    .clipShape(Capsule())
                }
                .padding(.top, 2)
            }

            Text(isAmountLocked ? lockedAmountHelperText : amountHelperText)
                .font(.caption)
                .foregroundColor(.white)
        }
    }

    private var amountUnitToggle: some View {
        HStack(spacing: 10) {
            unitButton(.usd)
            unitButton(.btc)
        }
        .disabled(isAmountLocked)
        .opacity(isAmountLocked ? 0.7 : 1.0)
    }

    private func unitButton(_ unit: AmountUnit) -> some View {
        let isSelected = (amountUnit == unit)

        return Button(action: {
            guard !isSelected else { return }
            amountUnit = unit
        }) {
            Text(unit.rawValue)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Color.white.opacity(isSelected ? 0.95 : 0.85))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? Color.splitBrandBlue : Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(isSelected ? 0.20 : 0.10), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var continueButton: some View {
        Button(action: continueTapped) {
            HStack(spacing: 8) {
                Image(systemName: "paperplane.fill")
                    .font(.headline)
                Text("Continue")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.splitBrandPink)
            .foregroundColor(.white)
            .cornerRadius(14)
        }
        .disabled(isPreparing || normalizedRequest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .opacity((isPreparing || normalizedRequest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? 0.6 : 1)
        .padding(.top, 4)
    }

    private var amountPlaceholder: String {
        switch amountUnit {
        case .usd: return "Amount in USD"
        case .btc: return "Amount in BTC"
        }
    }

    private var amountHelperText: String {
        "Some recipients (LNURL / Lightning addresses) require you to enter an amount."
    }

    private var lockedAmountHelperText: String {
        "This request includes a fixed amount."
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

    private func exitFlow() {
        if let onExitFlow {
            onExitFlow()
        } else {
            dismiss()
        }
    }

    private func completeAndExitFlow() {
        paymentPreview = nil
        exitFlow()
    }

    private func handleScanClose() {
        if shouldReturnToEntryAfterScan {
            statusMessage = nil
            shouldReturnToEntryAfterScan = false
            stage = .entry
        } else {
            exitFlow()
        }
    }

    private func openScannerFromEntry() {
        dismissKeyboard()
        statusMessage = nil
        shouldReturnToEntryAfterScan = true
        stage = .scan
    }

    private func showEntryStage(with paymentRequest: String) {
        recipientInput = paymentRequest
        updateNormalizedRequest(from: paymentRequest)
        statusMessage = nil
        shouldReturnToEntryAfterScan = false
        stage = .entry
    }

    private func showReviewStage(with preview: WalletManager.PaymentPreview) {
        paymentPreview = preview
        statusMessage = nil
        stage = .review
    }

    private func handleScannedCode(_ code: String) {
        if let payload = SplitContactPayload.parse(from: code) {
            handleScannedContactPayload(payload)
            return
        }

        guard let normalized = normalizePaymentRequest(from: code) else {
            statusMessage = "Couldn’t read a supported payment or contact QR."
            return
        }

        if shouldOpenEntryFirstSendFlow(for: normalized) {
            showEntryStage(with: normalized)
            return
        }

        preparePaymentForReview(paymentRequest: normalized, amountSatsOverride: nil, allowEntryFallback: true)
    }

    private func pasteFromClipboard() {
        guard let clipboardRaw = UIPasteboard.general.string,
              !clipboardRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            statusMessage = "Clipboard is empty or doesn’t contain text."
            return
        }

        if let payload = SplitContactPayload.parse(from: clipboardRaw) {
            handleScannedContactPayload(payload)
            return
        }

        guard let normalized = normalizePaymentRequest(from: clipboardRaw) else {
            statusMessage = "Clipboard text doesn’t contain a supported payment or contact code."
            return
        }

        if shouldOpenEntryFirstSendFlow(for: normalized) {
            showEntryStage(with: normalized)
            return
        }

        preparePaymentForReview(paymentRequest: normalized, amountSatsOverride: nil, allowEntryFallback: true)
    }

    private func updateNormalizedRequest(from raw: String) {
        statusMessage = nil

        let normalized = normalizePaymentRequest(from: raw)
        normalizedRequest = normalized ?? ""
        presetAmountSats = nil
        isAmountLocked = false

        guard let normalized, !normalized.isEmpty else {
            return
        }

        Task {
            let sats = await walletManager.presetAmountSatsIfBolt11(normalized)
            await MainActor.run {
                self.presetAmountSats = sats
                if let sats, sats > 0 {
                    self.isAmountLocked = true
                    self.syncLockedAmountDisplay()
                } else {
                    self.isAmountLocked = false
                }
            }
        }
    }

    private func handleScannedContactPayload(_ payload: SplitContactPayload) {
        do {
            if let verifiedBinding = try payload.verifiedIdentityBindingPayload() {
                try MessageRecipientTrustStore.enforceOrPin(verifiedBinding)
            }

            statusMessage = nil
            scannedContactPayload = payload
        } catch {
            statusMessage = error.localizedDescription
            scannedContactPayload = nil
        }
    }

    private func syncLockedAmountDisplay() {
        guard let sats = presetAmountSats, sats > 0 else { return }
        let btc = Double(sats) / 100_000_000.0

        switch amountUnit {
        case .btc:
            amountText = formatBTC(btc)
        case .usd:
            if let rate = walletManager.btcUsdRate, rate > 0 {
                amountText = formatUSD(btc * rate)
            } else {
                amountText = formatBTC(btc)
            }
        }
    }

    private func normalizePaymentRequest(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()

        if lower.hasPrefix("lightning:") {
            let withoutScheme = String(trimmed.dropFirst("lightning:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return normalizePaymentRequest(from: withoutScheme) ?? withoutScheme
        }

        if lower.hasPrefix("bitcoin:") {
            if let components = URLComponents(string: trimmed),
               let queryItems = components.queryItems,
               let lnItem = queryItems.first(where: { $0.name.lowercased() == "lightning" }),
               let value = lnItem.value,
               !value.isEmpty {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                return trimmed
            }
        }

        if let url = URL(string: trimmed),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems,
           let lnItem = queryItems.first(where: { $0.name.lowercased() == "lightning" }),
           let value = lnItem.value,
           !value.isEmpty {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if trimmed.contains("@") && !trimmed.contains(" ") {
            return trimmed
        }

        if lower.hasPrefix("lnbc") || lower.hasPrefix("lntb") || lower.hasPrefix("lnbcrt") || lower.hasPrefix("lnurl") {
            return trimmed
        }

        return trimmed
    }

    private func shouldOpenEntryFirstSendFlow(for paymentRequest: String) -> Bool {
        let trimmed = paymentRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        if lower.hasPrefix("lnurl") {
            return true
        }

        if trimmed.contains("@") && !trimmed.contains(" ") {
            return true
        }

        return false
    }

    private func continueTapped() {
        statusMessage = nil
        dismissKeyboard()

        let request = normalizedRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else {
            statusMessage = "Enter a destination to send to."
            return
        }

        if isAmountLocked {
            preparePaymentForReview(paymentRequest: request, amountSatsOverride: nil, allowEntryFallback: false)
            return
        }

        Task {
            guard let overrideSats = await amountOverrideSatsForEntry() else { return }
            preparePaymentForReview(paymentRequest: request, amountSatsOverride: overrideSats, allowEntryFallback: false)
        }
    }

    @MainActor
    private func amountOverrideSatsForEntry() async -> UInt64? {
        let cleaned = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            statusMessage = "Enter an amount."
            return nil
        }

        let normalizedNumber = cleaned
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")

        guard let value = Double(normalizedNumber), value > 0 else {
            statusMessage = "Enter a valid amount."
            return nil
        }

        let btcAmount: Double?
        switch amountUnit {
        case .btc:
            btcAmount = value
        case .usd:
            btcAmount = await walletManager.convertUsdToBtc(usdAmount: value)
        }

        guard let btc = btcAmount, btc > 0 else {
            statusMessage = "Couldn’t convert USD to BTC. Try again."
            return nil
        }

        let satsDouble = btc * 100_000_000.0
        guard satsDouble.isFinite, satsDouble > 0 else {
            statusMessage = "Enter a valid amount."
            return nil
        }

        return UInt64(max(1, Int64(satsDouble.rounded())))
    }

    private func preparePaymentForReview(
        paymentRequest: String,
        amountSatsOverride: UInt64?,
        allowEntryFallback: Bool
    ) {
        statusMessage = nil
        isPreparing = true

        Task {
            let preview = await walletManager.preparePayment(
                paymentRequest: paymentRequest,
                amountSatsOverride: amountSatsOverride,
                lnurlComment: prefilledLnurlComment
            )

            await MainActor.run {
                isPreparing = false

                if let preview {
                    showReviewStage(with: preview)
                } else {
                    let lastError = walletManager.lastErrorMessage ?? "Couldn’t prepare payment."
                    if allowEntryFallback && lastError == "Enter an amount in sats." {
                        showEntryStage(with: paymentRequest)
                    } else {
                        statusMessage = lastError
                    }
                }
            }
        }
    }

    private func formatBTC(_ btc: Double) -> String {
        String(format: "%.8f", btc)
            .replacingOccurrences(of: #"(\.\d*?[1-9])0+$"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\.0+$"#, with: "", options: .regularExpression)
    }

    private func formatUSD(_ usd: Double) -> String {
        String(format: "%.2f", usd)
    }
}
