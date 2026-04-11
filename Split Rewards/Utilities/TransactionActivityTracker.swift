//
//  TransactionActivityTracker.swift
//  Split Rewards
//
//

import Foundation

@MainActor
final class TransactionActivityTracker: ObservableObject {
    static let shared = TransactionActivityTracker()

    @Published private(set) var unseenTransactionIDs: Set<String> = []

    private let seenTransactionIDsKey = "split.seenTransactionIDs"
    private let hasSeededSeenTransactionsKey = "split.hasSeededSeenTransactions"

    private init() {
        unseenTransactionIDs = []
    }

    var unseenCount: Int {
        unseenTransactionIDs.count
    }

    func refreshIfPossible(walletManager: WalletManager) async {
        guard case .ready = walletManager.state else {
            unseenTransactionIDs = []
            return
        }

        do {
            let rows = try await walletManager.fetchTransactionRowsFromBreez()
            reconcile(with: rows)
        } catch {
            // Leave the current badge state alone if refresh fails.
        }
    }

    func reconcile(with rows: [WalletManager.TransactionRow]) {
        let currentIDs = Set(rows.map(\.id))

        if !hasSeededSeenTransactions {
            persistSeenTransactionIDs(currentIDs)
            hasSeededSeenTransactions = true
            unseenTransactionIDs = []
            return
        }

        let persistedSeenIDs = loadSeenTransactionIDs()
        let prunedSeenIDs = persistedSeenIDs.intersection(currentIDs)

        if prunedSeenIDs != persistedSeenIDs {
            persistSeenTransactionIDs(prunedSeenIDs)
        }

        unseenTransactionIDs = currentIDs.subtracting(prunedSeenIDs)
    }

    func captureVisibleUnseenAndMarkSeen(_ rows: [WalletManager.TransactionRow]) -> Set<String> {
        let currentIDs = Set(rows.map(\.id))
        let visibleUnseenIDs = unseenTransactionIDs.intersection(currentIDs)

        markSeen(currentIDs)

        return visibleUnseenIDs
    }

    func markSeen(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }

        var seenIDs = loadSeenTransactionIDs()
        seenIDs.formUnion(ids)
        persistSeenTransactionIDs(seenIDs)
        unseenTransactionIDs.subtract(ids)
    }

    private var hasSeededSeenTransactions: Bool {
        get { UserDefaults.standard.bool(forKey: hasSeededSeenTransactionsKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasSeededSeenTransactionsKey) }
    }

    private func loadSeenTransactionIDs() -> Set<String> {
        let storedIDs = UserDefaults.standard.stringArray(forKey: seenTransactionIDsKey) ?? []
        return Set(storedIDs)
    }

    private func persistSeenTransactionIDs(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids), forKey: seenTransactionIDsKey)
    }
}

extension Notification.Name {
    static let walletTransactionsDidChange = Notification.Name("walletTransactionsDidChange")
}
