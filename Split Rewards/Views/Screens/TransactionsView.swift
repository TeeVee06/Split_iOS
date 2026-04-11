//  TransactionsView.swift
//  Split Rewards
//
//
import SwiftUI
import UIKit

struct TransactionsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var walletManager: WalletManager
    @EnvironmentObject private var authManager: AuthManager

    // Brand
    let blue = Color.splitBrandBlue
    private let pink = Color.splitBrandPink

    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var transactions: [WalletManager.TransactionRow] = []
    @State private var highlightedTransactionIDs: Set<String> = []
    @State private var postedTransactionIDs: Set<String> = []
    @State private var reportableTransactionIDs: Set<String> = []
    @State private var composerTransaction: WalletManager.TransactionRow?
    @State private var selectedTransaction: WalletManager.TransactionRow?
    @State private var merchantReportTransaction: WalletManager.TransactionRow?
    @State private var reportableTransaction: WalletManager.TransactionRow?
    @StateObject private var composerDraft = ProofOfSpendComposerDraft(placeText: "")
    @StateObject private var transactionActivityTracker = TransactionActivityTracker.shared

    var body: some View {
        ZStack {
            Color.black.opacity(0.95)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                header

                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 12)

                } else if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .padding(.top, 8)

                } else if transactions.isEmpty {
                    Text("No transactions yet.")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.70))
                        .padding(.top, 8)

                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(transactions) { tx in
                                TransactionCard(
                                    tx: tx,
                                    accentColor: pink,
                                    showsNewActivity: highlightedTransactionIDs.contains(tx.id),
                                    hasProofOfSpendPost: postedTransactionIDs.contains(tx.id),
                                    isReportable: reportableTransactionIDs.contains(tx.id),
                                    onOpenDetails: {
                                        selectedTransaction = tx
                                    },
                                    onReportMerchant: {
                                        merchantReportTransaction = tx
                                    },
                                    onManageReportability: {
                                        reportableTransaction = tx
                                    },
                                    onCreateProofOfSpend: {
                                        composerDraft.reset(
                                            placeText: tx.note.trimmingCharacters(in: .whitespacesAndNewlines)
                                        )
                                        composerTransaction = tx
                                    }
                                )
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding()
        }
        .task { await refresh() }
        .refreshable { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .walletTransactionsDidChange)) { _ in
            Task {
                await refresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .proofOfSpendPostDidCreate)) { _ in
            if let composerTransaction {
                postedTransactionIDs.insert(composerTransaction.id)
            }
            composerTransaction = nil
            dismiss()
        }
        .sheet(item: $composerTransaction) { tx in
            ProofOfSpendShareComposer(
                tx: tx,
                onPostCreated: {
                    postedTransactionIDs.insert(tx.id)
                    composerTransaction = nil
                },
                draft: composerDraft
            )
        }
        .sheet(item: $selectedTransaction) { tx in
            TransactionDetailView(tx: tx)
        }
        .sheet(item: $merchantReportTransaction) { tx in
            MerchantPubkeyReportSheet(tx: tx)
                .environmentObject(walletManager)
                .environmentObject(authManager)
        }
        .sheet(item: $reportableTransaction) { tx in
            TransactionReportableSheet(
                tx: tx,
                isInitiallyReportable: reportableTransactionIDs.contains(tx.id),
                onStatusChanged: { isReportable in
                    updateReportableStatus(for: tx.id, isReportable: isReportable)
                }
            )
            .environmentObject(walletManager)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Transactions")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Spacer(minLength: 0)

            TransactionExportButton(
                transactions: transactions,
                walletManager: walletManager,
                accentColor: pink
            )
        }
    }

    @MainActor
    private func refresh() async {
        isLoading = true
        errorMessage = nil

        do {
            let rows = try await walletManager.fetchTransactionRowsFromBreez()
            transactions = rows
            transactionActivityTracker.reconcile(with: rows)
            highlightedTransactionIDs.formUnion(
                transactionActivityTracker.captureVisibleUnseenAndMarkSeen(rows)
            )
            postedTransactionIDs = await loadPostedTransactionIDs()
            reportableTransactionIDs = await loadReportableTransactionIDs(for: rows)
        } catch {
            errorMessage = "Failed to load transactions."
        }

        isLoading = false
    }

    @MainActor
    private func loadPostedTransactionIDs() async -> Set<String> {
        do {
            let posts = try await GetMyPOSFeedPostsAPI.fetchPosts(
                authManager: authManager,
                walletManager: walletManager
            )
            return Set(posts.map(\.transactionId))
        } catch {
            return []
        }
    }

    @MainActor
    private func loadReportableTransactionIDs(
        for rows: [WalletManager.TransactionRow]
    ) async -> Set<String> {
        guard let walletPubkey = try? await MessageKeyManager.shared.currentWalletPubkey(walletManager: walletManager) else {
            return []
        }

        let reportableStates = await PaymentUsdSnapshotStore.shared.reportableStates(
            walletPubkey: walletPubkey,
            paymentIds: rows.map(\.id)
        )

        return Set(
            reportableStates.compactMap { paymentId, isReportable in
                isReportable ? paymentId : nil
            }
        )
    }

    @MainActor
    private func updateReportableStatus(for paymentId: String, isReportable: Bool) {
        if isReportable {
            reportableTransactionIDs.insert(paymentId)
        } else {
            reportableTransactionIDs.remove(paymentId)
        }
    }
}

private struct TransactionCard: View {
    let tx: WalletManager.TransactionRow
    let accentColor: Color
    let showsNewActivity: Bool
    let hasProofOfSpendPost: Bool
    let isReportable: Bool
    let onOpenDetails: () -> Void
    let onReportMerchant: () -> Void
    let onManageReportability: () -> Void
    let onCreateProofOfSpend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            topLine

            Divider()
                .background(Color.white.opacity(0.10))
                .opacity(0.35)

            VStack(alignment: .leading, spacing: 8) {
                infoRow(label: "Status", value: tx.status)
                infoRow(label: "Network", value: tx.network.capitalized)
                infoRow(label: "Date", value: tx.dateString)

                if !tx.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    infoRow(label: "Note", value: tx.note)
                }

                if tx.feeSats > 0 {
                    infoRow(label: "Fee (BTC)", value: tx.feeBtcAmount)
                }

                HStack {
                    if canReportMerchant {
                    Button(action: onReportMerchant) {
                        Image(systemName: "storefront.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(Color.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add merchant for rewards")
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white.opacity(0.35))
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    showsNewActivity
                        ? Color.splitBrandBlue.opacity(0.78)
                        : Color.white.opacity(0.08),
                    lineWidth: 1
                )
        )
        .shadow(
            color: showsNewActivity
                ? Color.splitBrandBlue.opacity(0.14)
                : .clear,
            radius: 10,
            x: 0,
            y: 4
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture(perform: onOpenDetails)
    }

    private var cardBackground: some View {
        ZStack {
            Color.white.opacity(0.06)

            LinearGradient(
                colors: [
                    (showsNewActivity ? Color.splitBrandBlue : accentColor).opacity(0.12),
                    Color.white.opacity(0.02),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(0.55)
        }
    }

    private var topLine: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(tx.direction.capitalized)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)

                Text(signedAmountText)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.92))
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if canManageReportableStatus {
                    Button(action: onManageReportability) {
                        Image(systemName: "book.pages")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(isReportable ? accentColor : Color.white.opacity(0.88))
                            .padding(8)
                            .background(isReportable ? accentColor.opacity(0.18) : Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isReportable ? "Edit reportable status" : "Mark transaction as reportable")
                }

                if canCreateProofOfSpend {
                    Button(action: onCreateProofOfSpend) {
                        Image(systemName: "circle.rectangle.filled.pattern.diagonalline")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.splitBrandPink)
                            .padding(8)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Create Proof of Spend")
                }
            }
        }
    }

    private var isSent: Bool {
        tx.direction.lowercased() == "sent"
    }

    private var canCreateProofOfSpend: Bool {
        isSent && !hasProofOfSpendPost
    }

    private var canManageReportableStatus: Bool {
        isSent && tx.status == "Completed"
    }

    private var signedAmountText: String {
        let sign = isSent ? "−" : "+"
        return "\(sign)\(tx.btcAmount) BTC"
    }

    private var canReportMerchant: Bool {
        isSent && tx.network.lowercased() == "lightning" && tx.destinationPubkey != nil
    }

    @ViewBuilder
    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.60))
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.86))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TransactionReportableSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var walletManager: WalletManager

    let tx: WalletManager.TransactionRow
    let onStatusChanged: (Bool) -> Void

    @State private var isReportable: Bool
    @State private var errorMessage: String?
    @State private var isRevertingState = false
    @State private var persistenceTask: Task<Void, Never>?

    init(
        tx: WalletManager.TransactionRow,
        isInitiallyReportable: Bool,
        onStatusChanged: @escaping (Bool) -> Void
    ) {
        self.tx = tx
        self.onStatusChanged = onStatusChanged
        _isReportable = State(initialValue: isInitiallyReportable)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Reportable Status")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundColor(.white)

                            Text("Use this to decide whether this send should export as reportable in your CSV. Transactions stay non-reportable unless you turn this on.")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.70))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            Toggle(isOn: $isReportable) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(isReportable ? "Reportable" : "Non-reportable")
                                        .font(.system(size: 18, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)

                                    Text(toggleDetailText)
                                        .font(.footnote)
                                        .foregroundColor(.white.opacity(0.66))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .tint(Color.splitBrandPink)
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.splitInputSurface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        )

                        VStack(alignment: .leading, spacing: 8) {
                            Text("This payment")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundColor(.white)

                            reportSummaryRow(label: "Amount", value: "\(tx.btcAmount) BTC")
                            reportSummaryRow(label: "Date", value: tx.dateString)
                            reportSummaryRow(label: "Status", value: tx.status)

                            if !tx.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                reportSummaryRow(label: "Note", value: tx.note)
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.splitInputSurface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        )

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote.weight(.medium))
                                .foregroundColor(.red.opacity(0.92))
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Reportable")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .onChange(of: isReportable) { oldValue, newValue in
            persistReportableStatus(from: oldValue, to: newValue)
        }
        .onDisappear {
            persistenceTask?.cancel()
        }
    }

    private var toggleDetailText: String {
        isReportable
            ? "This transaction will export as Reportable."
            : "This transaction will export as Non-reportable."
    }

    private func persistReportableStatus(from oldValue: Bool, to newValue: Bool) {
        guard !isRevertingState else { return }
        guard oldValue != newValue else { return }

        errorMessage = nil
        onStatusChanged(newValue)
        persistenceTask?.cancel()

        persistenceTask = Task {
            do {
                let walletPubkey = try await MessageKeyManager.shared.currentWalletPubkey(walletManager: walletManager)
                await PaymentUsdSnapshotStore.shared.setReportable(
                    walletPubkey: walletPubkey,
                    paymentId: tx.id,
                    paymentType: tx.direction.lowercased() == "received" ? .received : .sent,
                    isReportable: newValue
                )
            } catch {
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    isRevertingState = true
                    isReportable = oldValue
                    onStatusChanged(oldValue)
                    errorMessage = "Unable to update the reportable setting on this device."
                    isRevertingState = false
                }
            }
        }
    }

    @ViewBuilder
    private func reportSummaryRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.60))
                .frame(width: 68, alignment: .leading)

            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.88))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct MerchantPubkeyReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var walletManager: WalletManager
    @EnvironmentObject private var authManager: AuthManager

    let tx: WalletManager.TransactionRow

    @State private var merchantName = ""
    @State private var merchantAddress = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Add Merchant")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundColor(.white)

                            Text("Share the merchant name and address. We’ll review the business and add them to rewards as quickly as possible.")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.70))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            inputField(
                                title: "Merchant Name",
                                text: $merchantName,
                                prompt: "Enter the business name"
                            )

                            inputField(
                                title: "Merchant Address",
                                text: $merchantAddress,
                                prompt: "Enter the business address"
                            )
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.splitInputSurface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        )

                        VStack(alignment: .leading, spacing: 8) {
                            Text("This payment")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundColor(.white)

                            reportSummaryRow(label: "Amount", value: "\(tx.btcAmount) BTC")
                            reportSummaryRow(label: "Date", value: tx.dateString)

                            if !tx.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                reportSummaryRow(label: "Note", value: tx.note)
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.splitInputSurface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        )

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote.weight(.medium))
                                .foregroundColor(.red.opacity(0.92))
                        }

                        Button {
                            submit()
                        } label: {
                            Group {
                                if isSubmitting {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Add Merchant")
                                        .font(.system(size: 17, weight: .bold))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(canSubmit ? Color.splitBrandPink : Color.white.opacity(0.08))
                            )
                            .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSubmit || isSubmitting)
                    }
                    .padding(16)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Add Merchant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }

    private var canSubmit: Bool {
        !merchantName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !merchantAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private func inputField(title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.65))

            TextField("", text: text, prompt: Text(prompt).foregroundColor(.white.opacity(0.35)))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.splitInputSurfaceSecondary)
                )
                .foregroundColor(.white)
        }
    }

    @ViewBuilder
    private func reportSummaryRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.60))
                .frame(width: 68, alignment: .leading)

            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.88))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func submit() {
        guard !isSubmitting else { return }

        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                try await postMerchantPubkeyReport(
                    walletManager: walletManager,
                    authManager: authManager,
                    transaction: tx,
                    merchantName: merchantName,
                    merchantAddress: merchantAddress
                )
                await MainActor.run {
                    isSubmitting = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct TransactionDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let tx: WalletManager.TransactionRow

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        summaryCard

                        if showsCounterpartySection {
                            TransactionDetailSection(title: "Counterparty") {
                                if tx.direction.lowercased() == "sent",
                                   let destinationPubkey = tx.destinationPubkey {
                                    TransactionCopyRow(
                                        label: "Destination Pubkey",
                                        value: destinationPubkey
                                    )
                                }

                                if let lnAddress = tx.lnAddress {
                                    TransactionCopyRow(
                                        label: "Lightning Address",
                                        value: lnAddress,
                                        useMonospacedFont: false
                                    )
                                }

                                if let domain = tx.lnurlDomain {
                                    TransactionValueRow(label: "LNURL Domain", value: domain)
                                }
                            }
                        }

                        if showsReferenceSection {
                            TransactionDetailSection(title: "Reference") {
                                if let label = tx.txReferenceLabel,
                                   let reference = tx.txReference {
                                    TransactionCopyRow(label: label, value: reference)
                                }

                                if let paymentHash = tx.paymentHash {
                                    TransactionCopyRow(label: "Payment Hash", value: paymentHash)
                                }

                                if let preimage = tx.preimage {
                                    TransactionCopyRow(label: "Preimage", value: preimage)
                                }

                                if let invoice = tx.invoice {
                                    TransactionCopyRow(label: "Invoice", value: invoice)
                                }

                                if let expiryDateString = tx.expiryDateString {
                                    TransactionValueRow(label: "HTLC Expiry", value: expiryDateString)
                                }
                            }
                        }

                        if showsNotesSection {
                            TransactionDetailSection(title: "Notes") {
                                if !tx.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    TransactionValueRow(label: "Note", value: tx.note)
                                }

                                if let lnurlComment = tx.lnurlComment {
                                    TransactionValueRow(label: "LNURL Comment", value: lnurlComment)
                                }

                                if let senderComment = tx.senderComment {
                                    TransactionValueRow(label: "Sender Comment", value: senderComment)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(tx.direction.capitalized)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.70))

                Text(signedAmountText)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)

                if !tx.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(tx.note)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.90))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                TransactionValueRow(label: "Status", value: tx.status)
                TransactionValueRow(label: "Method", value: tx.method)
                TransactionValueRow(label: "Network", value: tx.network.capitalized)
                TransactionValueRow(label: "Date", value: tx.dateString)
                TransactionValueRow(label: "Fee (BTC)", value: tx.feeBtcAmount)

                if tx.hasConversion {
                    TransactionValueRow(label: "Conversion", value: "Yes")
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.splitInputSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var signedAmountText: String {
        let sign = tx.direction.lowercased() == "sent" ? "−" : "+"
        return "\(sign)\(tx.btcAmount) BTC"
    }

    private var showsCounterpartySection: Bool {
        (tx.direction.lowercased() == "sent" && tx.destinationPubkey != nil)
            || tx.lnAddress != nil
            || tx.lnurlDomain != nil
    }

    private var showsReferenceSection: Bool {
        tx.txReference != nil
            || tx.paymentHash != nil
            || tx.preimage != nil
            || tx.invoice != nil
            || tx.expiryDateString != nil
    }

    private var showsNotesSection: Bool {
        !tx.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || tx.lnurlComment != nil
            || tx.senderComment != nil
    }
}

private struct TransactionDetailSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.splitInputSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
    }
}

private struct TransactionValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.60))
                .frame(width: 110, alignment: .leading)

            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.88))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TransactionCopyRow: View {
    let label: String
    let value: String
    var useMonospacedFont: Bool = true

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.60))
                .frame(width: 110, alignment: .leading)

            Text(value)
                .font(
                    useMonospacedFont
                    ? .system(size: 13, weight: .medium, design: .monospaced)
                    : .system(size: 14, weight: .medium)
                )
                .foregroundColor(.white.opacity(0.88))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            Button {
                UIPasteboard.general.string = value
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color.splitBrandPink)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy \(label)")
        }
    }
}

#Preview {
    TransactionsView()
        .environmentObject(WalletManager())
        .environmentObject(AuthManager())
}
