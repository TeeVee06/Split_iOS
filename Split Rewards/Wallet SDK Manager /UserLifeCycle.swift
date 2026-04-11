//
//  UserLifeCycle.swift
//  Split Rewards
//
//
import Foundation
import BreezSdkSpark

@MainActor
extension WalletManager {

    // MARK: - Public API (called from the app)

    /// Main entry point: connect to Breez if a local seed exists.
    /// Caller must supply AuthManager so wallet events can trigger
    /// authenticated backend calls.
    func configure(authManager: AuthManager) async {
        if isConfiguring {
            print("⚠️ [WalletManager \(instanceId)] configure() already running – skipping re-entry")
            return
        }

        isConfiguring = true
        defer { isConfiguring = false }

        lastErrorMessage = nil

        if let seed = readLocalSeed() {
            print("ℹ️ [WalletManager \(instanceId)] configure(): found local seed, connecting with seed")
            await connectWithSeed(seed, authManager: authManager)
        } else {
            print("ℹ️ [WalletManager \(instanceId)] configure(): no local seed → disconnecting, state = .noWallet")
            await disconnectCurrentWallet()
            state = .noWallet
        }
    }

    /// Force a re-fetch of wallet info from Breez.
    func refreshWalletState() async {
        lastErrorMessage = nil

        do {
            try await loadRemoteState()
            await refreshBtcUsdRate()
            updateFiatBalance()
        } catch {
            let msg = "Failed to refresh wallet: \(error.localizedDescription)"
            state = .error(msg)
            lastErrorMessage = msg
        }
    }

    // MARK: - Connection & state loading

    func connectWithSeed(
        _ mnemonic: String,
        authManager: AuthManager,
        persistSeedOnSuccess: Bool = false
    ) async {
        lastErrorMessage = nil

        do {
            if let existing = sdk {
                do {
                    await detachEventListener()
                    try await existing.disconnect()
                } catch {
                    print("⚠️ [WalletManager \(instanceId)] Breez disconnect failed: \(error)")
                }
            }

            let seed = Seed.mnemonic(mnemonic: mnemonic, passphrase: nil)
            let apiKey = try await getBreezApiKey()

            var config = defaultConfig(network: .mainnet)
            config.apiKey = apiKey
            config.lnurlDomain = AppConfig.lightningAddressDomain
            config.privateEnabledDefault = true

            let storageDir = try makeStorageDir()

            let newSdk = try await connect(
                request: ConnectRequest(
                    config: config,
                    seed: seed,
                    storageDir: storageDir
                )
            )

            sdk = newSdk

            if persistSeedOnSuccess {
                saveLocalSeed(mnemonic)
            }

            await attachEventListener(
                to: newSdk,
                authManager: authManager
            )

            try await loadRemoteState()
            do {
                _ = try await MessageKeyManager.shared.ensureRegistered(
                    authManager: authManager,
                    walletManager: self
                )
                await MessagingDeviceTokenManager.shared.syncDeviceTokenIfPossible(
                    authManager: authManager,
                    walletManager: self,
                    force: true
                )
                await MessageSyncManager.shared.syncInboxIfPossible(
                    authManager: authManager,
                    walletManager: self,
                    force: true
                )
                _ = await MessagingPushSyncCoordinator.shared.processPendingPushIfPossible()
            } catch {
                if MessageKeyManager.shared.shouldSilentlyDeferActivation(for: error) {
                    print("ℹ️ [WalletManager \(instanceId)] Messaging activation deferred: \(error.localizedDescription)")
                } else {
                    print("⚠️ [WalletManager \(instanceId)] Messaging key ensure failed: \(error.localizedDescription)")
                }
            }

            await refreshBtcUsdRate()
            updateFiatBalance()
        } catch {
            let msg = "Failed to connect wallet: \(error.localizedDescription)"

            if shouldResetStoredSeedAfterConnectionFailure(error) {
                await disconnectCurrentWallet()
                clearLocalSeed()
                state = .noWallet
            } else {
                state = .error(msg)
            }

            lastErrorMessage = msg
        }
    }

    func loadRemoteState() async throws {
        guard let sdk else { throw WalletError.sdkNotInitialized }

        let info = try await sdk.getInfo(
            request: GetInfoRequest(ensureSynced: false)
        )

        await MainActor.run {
            self.balanceSats = info.balanceSats
            self.updateFiatBalance()
            self.state = .ready
        }
    }

    // MARK: - Wallet removal

    /// Remove the wallet from this device.
    /// This deletes the locally stored seed, clears Breez local storage,
    /// and disconnects from Breez.
    /// Restoration is only possible using the recovery phrase.
    func removeWalletFromThisDevice() async {
        // 1) Stop Breez + clear in-memory state
        await disconnectCurrentWallet()

        // 2) Delete seed from Keychain (irreversible without phrase)
        clearLocalSeed()

        // 3) Delete messaging identity + local messages so device-scoped chat state is wiped
        MessageKeyManager.shared.clearStoredMessagingKey()
        SecureMessagingStorage.shared.clearStoredKey()
        MessagingDeviceTokenManager.shared.clearCachedDeviceTokenState()
        MessageRecipientTrustStore.clearAll()
        clearCachedLightningAddress()
        MessageStore.shared.clearAll()
        MessageAttachmentManager.shared.clearAll()
        await PaymentUsdSnapshotStore.shared.clearAll()

        // 4) Delete Breez local storage so stale SDK state cannot survive
        clearBreezStorage()

        // 5) Reset UI state
        state = .noWallet
        lastErrorMessage = nil
    }

    // MARK: - Internal teardown

    private func disconnectCurrentWallet() async {
        await detachEventListener()

        if let existing = sdk {
            do {
                try await existing.disconnect()
            } catch {
                print("⚠️ [WalletManager \(instanceId)] Breez disconnect failed: \(error)")
            }
        }

        sdk = nil
        balanceSats = 0
        fiatBalanceUSD = nil
        btcUsdRate = nil
        processedPaymentIds.removeAll()
        usdSnapshotSyncTask?.cancel()
        usdSnapshotSyncTask = nil
    }

    // MARK: - Seed storage helpers

    private func readLocalSeed() -> String? {
        KeychainHelper.read(forKey: walletSeedKey)
    }

    func saveLocalSeed(_ seed: String) {
        KeychainHelper.save(seed, forKey: walletSeedKey)
    }

    private func clearLocalSeed() {
        KeychainHelper.delete(forKey: walletSeedKey)
    }

    // MARK: - Storage dir & fiat balance

    private func makeStorageDir() throws -> String {
        let fm = FileManager.default
        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let dir = appSupport.appendingPathComponent("breez-spark", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    private func clearBreezStorage() {
        do {
            let fm = FileManager.default
            let appSupport = try fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )

            let dir = appSupport.appendingPathComponent("breez-spark", isDirectory: true)

            if fm.fileExists(atPath: dir.path) {
                try fm.removeItem(at: dir)
                print("🧹 [WalletManager \(instanceId)] Cleared Breez storage: \(dir.path)")
            } else {
                print("ℹ️ [WalletManager \(instanceId)] No Breez storage found to clear at: \(dir.path)")
            }
        } catch {
            print("⚠️ [WalletManager \(instanceId)] Failed to clear Breez storage: \(error)")
        }
    }

    func updateFiatBalance() {
        Task { @MainActor in
            guard sdk != nil else { return }
            guard let rate = btcUsdRate else {
                fiatBalanceUSD = nil
                return
            }

            let btc = Double(balanceSats) / 100_000_000.0
            fiatBalanceUSD = btc * rate
        }
    }

    private func shouldResetStoredSeedAfterConnectionFailure(_ error: Error) -> Bool {
        let normalizedDescription = error.localizedDescription.lowercased()

        guard normalizedDescription.contains("mnemonic") else {
            return false
        }

        return normalizedDescription.contains("unknown word")
            || normalizedDescription.contains("unknow word")
            || normalizedDescription.contains("invalid mnemonic")
            || normalizedDescription.contains("invalid word")
            || normalizedDescription.contains("mnemonic contains")
    }
}
