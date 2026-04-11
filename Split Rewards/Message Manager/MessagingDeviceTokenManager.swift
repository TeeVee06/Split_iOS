//
//  MessagingDeviceTokenManager.swift
//  Split Rewards
//
//

import Foundation
import UIKit
import UserNotifications

@MainActor
final class MessagingDeviceTokenManager: ObservableObject {
    static let shared = MessagingDeviceTokenManager()

    private let currentTokenDefaultsKey = "split.messaging.apns.currentToken"
    private let syncedTokenDefaultsKey = "split.messaging.apns.syncedToken"
    private let syncedMessagingPubkeyDefaultsKey = "split.messaging.apns.syncedMessagingPubkey"
    private let syncedEnvironmentDefaultsKey = "split.messaging.apns.syncedEnvironment"

    private init() {}

    var currentDeviceToken: String? {
        UserDefaults.standard.string(forKey: currentTokenDefaultsKey)
    }

    var syncedDeviceToken: String? {
        UserDefaults.standard.string(forKey: syncedTokenDefaultsKey)
    }

    var syncedMessagingPubkey: String? {
        UserDefaults.standard.string(forKey: syncedMessagingPubkeyDefaultsKey)
    }

    var syncedEnvironment: String? {
        UserDefaults.standard.string(forKey: syncedEnvironmentDefaultsKey)
    }

    func registerForRemoteNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, error in
            if let error {
                print("Failed to request notification authorization: \(error.localizedDescription)")
            }

            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func updateAPNsDeviceToken(_ deviceToken: Data) {
        let hexToken = deviceToken.map { String(format: "%02x", $0) }.joined()
        let defaults = UserDefaults.standard

        if defaults.string(forKey: currentTokenDefaultsKey) != hexToken {
            defaults.set(hexToken, forKey: currentTokenDefaultsKey)
            defaults.removeObject(forKey: syncedTokenDefaultsKey)
            defaults.removeObject(forKey: syncedMessagingPubkeyDefaultsKey)
            defaults.removeObject(forKey: syncedEnvironmentDefaultsKey)
        }
    }

    func clearCachedDeviceTokenState() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: currentTokenDefaultsKey)
        defaults.removeObject(forKey: syncedTokenDefaultsKey)
        defaults.removeObject(forKey: syncedMessagingPubkeyDefaultsKey)
        defaults.removeObject(forKey: syncedEnvironmentDefaultsKey)
    }

    func unregisterDeviceTokenIfPossible(
        authManager: AuthManager,
        walletManager: WalletManager
    ) async {
        guard case .ready = walletManager.state else { return }

        clearCachedDeviceTokenState()
    }

    func syncDeviceTokenIfPossible(
        authManager: AuthManager,
        walletManager: WalletManager,
        force: Bool = false
    ) async {
        guard case .ready = walletManager.state else { return }
        guard let currentDeviceToken else {
            return
        }

        do {
            let registration = try await MessageKeyManager.shared.ensureRegistered(
                authManager: authManager,
                walletManager: walletManager
            )
            guard let activeMessagingPubkey = registration.messagingPubkey?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
                  !activeMessagingPubkey.isEmpty else {
                return
            }

            if !force,
               syncedDeviceToken == currentDeviceToken,
               syncedMessagingPubkey == activeMessagingPubkey,
               syncedEnvironment == AppConfig.messagingPushEnvironment {
                return
            }

            _ = try await MessagingDeviceTokenAPI.registerDeviceToken(
                currentDeviceToken,
                messagingPubkey: activeMessagingPubkey,
                authManager: authManager,
                walletManager: walletManager
            )
            let defaults = UserDefaults.standard
            defaults.set(currentDeviceToken, forKey: syncedTokenDefaultsKey)
            defaults.set(activeMessagingPubkey, forKey: syncedMessagingPubkeyDefaultsKey)
            defaults.set(AppConfig.messagingPushEnvironment, forKey: syncedEnvironmentDefaultsKey)
        } catch let urlError as URLError where urlError.code == .cancelled {
            return
        } catch {
            guard !MessageKeyManager.shared.shouldSilentlyDeferActivation(for: error) else {
                return
            }
            print("Failed to sync messaging device token: \(error.localizedDescription)")
        }
    }
}
