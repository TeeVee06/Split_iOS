//  WalletManager.swift
//  Split Rewards
//
//
import Foundation
import Combine
import BreezSdkSpark
import Bip39          // BIP39 seed phrase
import BigNumber      // BInt used by Breez Spark for some amounts

/// High-level state for the BTC/Spark wallet UI.
@MainActor
final class WalletManager: ObservableObject {
    
    // MARK: - Types
    
    enum WalletState: Equatable {
        case loading
        case noWallet           // No wallet configured on this device
        case ready              // Connected and usable
        case error(String)      // Fatal-ish error to show in the UI
    }
    
    enum WalletError: Error {
        case sdkNotInitialized
        case invalidSeedPhrase
    }
    
    /// Lightweight data model for the "review & confirm" send screen.
    struct PaymentPreview: Identifiable, Equatable {
        let id: UUID
        
        /// The raw invoice / address / Spark address string.
        let paymentRequest: String
        
        /// Amount to send in sats. For amountless invoices this can be 0.
        let amountSats: UInt64
        
        /// Optional USD equivalent for the amount, if we have a BTC/USD rate.
        let amountFiatUSD: Double?
        
        /// Estimated routing / network fee in sats (if known).
        /// Populated from the Breez `PrepareSendPaymentResponse.paymentMethod`.
        let routingFeeSats: UInt64?
        
        /// Optional human-readable recipient label (if available).
        let recipientName: String?
    }
    
    // MARK: - Published properties used by SwiftUI
    
    @Published var state: WalletState = .loading
    @Published var balanceSats: UInt64 = 0
    @Published var fiatBalanceUSD: Double? = nil
    @Published var isSyncing: Bool = false
    @Published var lastErrorMessage: String?
    
    /// When the user taps “Create Wallet”, we generate a mnemonic and store it here.
    /// The UI can show a SeedPhraseBackupView while this is non-nil.
    @Published var pendingSeedPhrase: String?
    @Published var pendingSeedWords: [String] = []
    
    // MARK: - External collaborators
    
    /// Optional global toast manager, injected from the app root.
    /// Used to show payment-related toasts on Breez events.
    var toastManager: ToastManager?
    
    // MARK: - Private-ish state (internal so extensions can mutate)
    
    /// Live Breez SDK instance (Spark)
    var sdk: BreezSdk?
    
    /// Key for wallet seed in Keychain (single wallet per device).
    let walletSeedKey = KeychainHelper.walletSeedKey
    
    /// In-memory cache of prepared payments, keyed by preview ID.
    ///
    /// We cache both the standard prepare response (BOLT11 / BTC address / Spark)
    /// and LNURL-pay prepares (including Lightning Addresses).
    enum PreparedPayment {
        case send(PrepareSendPaymentResponse)
        case lnurl(PrepareLnurlPayResponse)
    }

    var preparedPayments: [UUID: PreparedPayment] = [:]
    
    /// Cached BTC→USD rate from Breez fiat rates.
    /// Used to compute USD equivalents for amounts and fees.
    @Published var btcUsdRate: Double?

    /// Current Breez event listener and its registration ID.
    var eventListener: WalletEventListener?
    var eventListenerId: String?
    
    /// Guard to prevent overlapping configure()/connect cycles that can stack listeners.
    var isConfiguring: Bool = false
    
    /// Simple instance counter to help debug multiple instances (if they ever occur).
    static var instanceCounter: Int = 0
    let instanceId: Int
    
    /// Set of payment identifiers we've already sent to the backend (per app lifetime).
    /// Key is `paymentHash` if available, otherwise `payment.id`.
    var processedPaymentIds = Set<String>()
    
    // MARK: - Refresh coalescing (debounce)
    /// Coalesce multiple Breez events into a single refresh.
    private var refreshTask: Task<Void, Never>?
    private let refreshDebounceNanos: UInt64 = 300_000_000 // 300ms
    var usdSnapshotSyncTask: Task<Void, Never>?
    
    /// Schedule a single refresh soon; multiple calls within the debounce window collapse into one.
    func scheduleRefresh() {
        // If a refresh is already scheduled/running, do nothing.
        if refreshTask != nil { return }
        
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            
            // Small debounce to collapse event storms (pending->succeeded->synced etc.)
            try? await Task.sleep(nanoseconds: self.refreshDebounceNanos)
            
            self.isSyncing = true
            defer {
                self.isSyncing = false
                self.refreshTask = nil
            }
            
            do {
                try await self.loadRemoteState()
                self.updateFiatBalance()
            } catch {
                let msg = "Failed to sync wallet: \(error.localizedDescription)"
                self.lastErrorMessage = msg
                // Do not hard-fail wallet state to .error just because a refresh failed;
                // let the UI keep functioning and retry on next event / manual refresh.
                print("⚠️ [WalletManager \(self.instanceId)] scheduleRefresh failed: \(msg)")
            }
        }
    }
    
    // MARK: - Init
    
    init() {
        WalletManager.instanceCounter += 1
        instanceId = WalletManager.instanceCounter
        print("🧠 WalletManager init – instanceId=\(instanceId)")
        state = .loading
    }
    
    deinit {
        print("🧠 WalletManager deinit – instanceId=\(instanceId)")
    }
    
    // MARK: - Convenience accessors
    
    /// Human-readable sats balance for display.
    var formattedSatsBalance: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: balanceSats)) ?? "\(balanceSats)"
    }
    
    /// BTC balance (from sats) as a fixed 8-decimal string.
    // Define this as a static constant so it's only created once
    private static let btcFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 8
        f.maximumFractionDigits = 8
        return f
    }()

    var formattedBTCBalance: String {
        let btc = Double(balanceSats) / 100_000_000.0
        return Self.btcFormatter.string(from: NSNumber(value: btc)) ?? "0.00000000"
    }
}

// MARK: - Helpers

extension Optional where Wrapped == String {
    /// Treat nil, empty, or all-whitespace strings as nil.
    var nilIfBlank: String? {
        guard let self = self else { return nil }
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension WalletManager {
    
    /// "Market" BTC price in USD from Breez fiat rates.
    var formattedBtcUsdPrice: String {
        guard let rate = btcUsdRate else { return "$—" }
        
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = "USD"
        nf.maximumFractionDigits = 2
        
        return nf.string(from: NSNumber(value: rate)) ?? "$—"
    }
    
    func refreshBtcPriceFromCoinbase() {
        fetchBitcoinPriceUSD(
            onSuccess: { [weak self] price in
                guard let self else { return }
                self.btcUsdRate = price
                self.updateFiatBalance()
            },
            onError: { error in
                print("⚠️ Coinbase BTC price fetch failed:", error)
            }
        )
    }
}




