//
//  Split_RewardsTests.swift
//  Split RewardsTests
//
//

import Testing
@testable import Split_Rewards

struct Split_RewardsTests {

    @Test func paymentUsdSnapshotDecodesExistingStoredSnapshotsAsNonReportable() throws {
        let json = """
        {
          "walletPubkey": "wallet-pubkey",
          "paymentId": "payment-id",
          "paymentType": "sent",
          "usdValueAtTransaction": 81.23,
          "btcUsdRateAtTransaction": 90234.12
        }
        """

        let snapshot = try JSONDecoder().decode(
            PaymentUsdSnapshot.self,
            from: Data(json.utf8)
        )

        #expect(snapshot.walletPubkey == "wallet-pubkey")
        #expect(snapshot.paymentId == "payment-id")
        #expect(snapshot.paymentType == .sent)
        #expect(snapshot.isReportable == false)
        #expect(snapshot.hasUsdSnapshot == true)
    }

    @Test func messagingDirectoryCheckpointScopesByBackendOrigin() throws {
        MessageDirectoryCheckpointStore.clear()
        defer { MessageDirectoryCheckpointStore.clear() }

        try MessageDirectoryCheckpointStore.storeIfNewer(
            MessagingDirectoryCheckpoint(
                rootHash: "prod-root",
                treeSize: 7,
                issuedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            scope: "https://prod.split.example"
        )

        try MessageDirectoryCheckpointStore.storeIfNewer(
            MessagingDirectoryCheckpoint(
                rootHash: "dev-root",
                treeSize: 7,
                issuedAt: Date(timeIntervalSince1970: 1_700_000_100)
            ),
            scope: "https://dev.split.example"
        )
    }

    @Test func messagingDirectoryCheckpointStillRejectsSameOriginConflicts() throws {
        MessageDirectoryCheckpointStore.clear()
        defer { MessageDirectoryCheckpointStore.clear() }

        try MessageDirectoryCheckpointStore.storeIfNewer(
            MessagingDirectoryCheckpoint(
                rootHash: "root-a",
                treeSize: 7,
                issuedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            scope: "https://prod.split.example"
        )

        do {
            try MessageDirectoryCheckpointStore.storeIfNewer(
                MessagingDirectoryCheckpoint(
                    rootHash: "root-b",
                    treeSize: 7,
                    issuedAt: Date(timeIntervalSince1970: 1_700_000_100)
                ),
                scope: "https://prod.split.example"
            )
            Issue.record("Expected a same-origin checkpoint conflict.")
        } catch let error as MessageDirectoryCheckpointStore.CheckpointError {
            switch error {
            case .conflictingCheckpoint:
                break
            case .staleCheckpoint:
                Issue.record("Expected a conflicting checkpoint, got stale.")
            }
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }
    }

}
