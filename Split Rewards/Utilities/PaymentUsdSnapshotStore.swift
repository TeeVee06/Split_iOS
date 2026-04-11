//
//  PaymentUsdSnapshotStore.swift
//  Split Rewards
//
//

import Foundation

struct PaymentUsdSnapshot: Codable, Equatable {
    enum PaymentType: String, Codable {
        case sent
        case received
    }

    let walletPubkey: String
    let paymentId: String
    let paymentType: PaymentType
    let usdValueAtTransaction: Double?
    let btcUsdRateAtTransaction: Double?
    let isReportable: Bool

    enum CodingKeys: String, CodingKey {
        case walletPubkey
        case paymentId
        case paymentType
        case usdValueAtTransaction
        case btcUsdRateAtTransaction
        case isReportable
    }

    init(
        walletPubkey: String,
        paymentId: String,
        paymentType: PaymentType,
        usdValueAtTransaction: Double? = nil,
        btcUsdRateAtTransaction: Double? = nil,
        isReportable: Bool = false
    ) {
        self.walletPubkey = walletPubkey
        self.paymentId = paymentId
        self.paymentType = paymentType
        self.usdValueAtTransaction = usdValueAtTransaction
        self.btcUsdRateAtTransaction = btcUsdRateAtTransaction
        self.isReportable = isReportable
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        walletPubkey = try container.decode(String.self, forKey: .walletPubkey)
        paymentId = try container.decode(String.self, forKey: .paymentId)
        paymentType = try container.decode(PaymentType.self, forKey: .paymentType)
        usdValueAtTransaction = try container.decodeIfPresent(Double.self, forKey: .usdValueAtTransaction)
        btcUsdRateAtTransaction = try container.decodeIfPresent(Double.self, forKey: .btcUsdRateAtTransaction)
        isReportable = try container.decodeIfPresent(Bool.self, forKey: .isReportable) ?? false
    }

    var hasUsdSnapshot: Bool {
        usdValueAtTransaction != nil && btcUsdRateAtTransaction != nil
    }

    func merging(snapshot: PaymentUsdSnapshot) -> PaymentUsdSnapshot {
        PaymentUsdSnapshot(
            walletPubkey: snapshot.walletPubkey,
            paymentId: snapshot.paymentId,
            paymentType: snapshot.paymentType,
            usdValueAtTransaction: snapshot.usdValueAtTransaction ?? usdValueAtTransaction,
            btcUsdRateAtTransaction: snapshot.btcUsdRateAtTransaction ?? btcUsdRateAtTransaction,
            isReportable: isReportable || snapshot.isReportable
        )
    }

    func withReportable(_ isReportable: Bool) -> PaymentUsdSnapshot {
        PaymentUsdSnapshot(
            walletPubkey: walletPubkey,
            paymentId: paymentId,
            paymentType: paymentType,
            usdValueAtTransaction: usdValueAtTransaction,
            btcUsdRateAtTransaction: btcUsdRateAtTransaction,
            isReportable: isReportable
        )
    }
}

actor PaymentUsdSnapshotStore {
    static let shared = PaymentUsdSnapshotStore()

    private var snapshotsByCompositeKey: [String: PaymentUsdSnapshot]?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {}

    func snapshot(walletPubkey: String, paymentId: String) -> PaymentUsdSnapshot? {
        let key = compositeKey(walletPubkey: walletPubkey, paymentId: paymentId)
        return loadSnapshots()[key]
    }

    func containsSnapshot(walletPubkey: String, paymentId: String) -> Bool {
        snapshot(walletPubkey: walletPubkey, paymentId: paymentId)?.hasUsdSnapshot == true
    }

    func snapshots(walletPubkey: String, paymentIds: [String]) -> [String: PaymentUsdSnapshot] {
        let allSnapshots = loadSnapshots()
        return paymentIds.reduce(into: [String: PaymentUsdSnapshot]()) { partialResult, paymentId in
            if let snapshot = allSnapshots[compositeKey(walletPubkey: walletPubkey, paymentId: paymentId)] {
                partialResult[paymentId] = snapshot
            }
        }
    }

    func reportableStates(walletPubkey: String, paymentIds: [String]) -> [String: Bool] {
        let allSnapshots = loadSnapshots()
        return paymentIds.reduce(into: [String: Bool]()) { partialResult, paymentId in
            if let snapshot = allSnapshots[compositeKey(walletPubkey: walletPubkey, paymentId: paymentId)] {
                partialResult[paymentId] = snapshot.isReportable
            }
        }
    }

    func upsert(_ snapshot: PaymentUsdSnapshot) {
        var snapshots = loadSnapshots()
        let key = compositeKey(walletPubkey: snapshot.walletPubkey, paymentId: snapshot.paymentId)
        if let existing = snapshots[key] {
            snapshots[key] = existing.merging(snapshot: snapshot)
        } else {
            snapshots[key] = snapshot
        }
        snapshotsByCompositeKey = snapshots
        persistSnapshots(snapshots)
    }

    func setReportable(
        walletPubkey: String,
        paymentId: String,
        paymentType: PaymentUsdSnapshot.PaymentType,
        isReportable: Bool
    ) {
        var snapshots = loadSnapshots()
        let key = compositeKey(walletPubkey: walletPubkey, paymentId: paymentId)

        if let existing = snapshots[key] {
            snapshots[key] = existing.withReportable(isReportable)
        } else {
            snapshots[key] = PaymentUsdSnapshot(
                walletPubkey: walletPubkey,
                paymentId: paymentId,
                paymentType: paymentType,
                isReportable: isReportable
            )
        }

        snapshotsByCompositeKey = snapshots
        persistSnapshots(snapshots)
    }

    func clearAll() {
        snapshotsByCompositeKey = [:]
        do {
            let fileURL = try storageFileURL()
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            print("⚠️ PaymentUsdSnapshotStore clear failed: \(error)")
        }
    }

    private func compositeKey(walletPubkey: String, paymentId: String) -> String {
        "\(walletPubkey)|\(paymentId)"
    }

    private func loadSnapshots() -> [String: PaymentUsdSnapshot] {
        if let snapshotsByCompositeKey {
            return snapshotsByCompositeKey
        }

        do {
            let fileURL = try storageFileURL()
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                snapshotsByCompositeKey = [:]
                return [:]
            }

            let data = try Data(contentsOf: fileURL)
            let snapshots = try decoder.decode([String: PaymentUsdSnapshot].self, from: data)
            snapshotsByCompositeKey = snapshots
            return snapshots
        } catch {
            print("⚠️ PaymentUsdSnapshotStore load failed: \(error)")
            snapshotsByCompositeKey = [:]
            return [:]
        }
    }

    private func persistSnapshots(_ snapshots: [String: PaymentUsdSnapshot]) {
        do {
            let fileURL = try storageFileURL()
            let data = try encoder.encode(snapshots)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("⚠️ PaymentUsdSnapshotStore persist failed: \(error)")
        }
    }

    private func storageFileURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let directory = appSupport.appendingPathComponent("payment-usd-snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("snapshots.json", isDirectory: false)
    }
}
