//
//  MessageKeyManager.swift
//  Split Rewards
//
//

import Foundation
import CryptoKit
import BreezSdkSpark

@MainActor
final class MessageKeyManager {
    static let shared = MessageKeyManager()

    private let legacyMessagingPrivateKeyKeychainKey = "split.messaging.privateKey"
    private let messagingV2PrivateKeyKeychainKeyBase = "split.messaging.v2.privateKey"
    private let messagingIdentityDomain = AppConfig.messagingIdentityDomain
    private let lightningAddressLookupRetryDelayNanoseconds: UInt64 = 500_000_000
    private let lightningAddressLookupMaxAttempts = 4

    private init() {}

    struct RegistrationResponse: Decodable {
        let ok: Bool
        let walletPubkey: String?
        let lightningAddress: String?
        let didUpdate: Bool?
        let didRotate: Bool?
        let messagingPubkey: String?
        let messagingIdentitySignature: String?
        let messagingIdentitySignatureVersion: Int?
        let messagingIdentitySignedAt: Date?
        let messagingIdentityUpdatedAt: Date?
        let directory: MessagingDirectoryProofPayload?
        let error: String?

        var normalizedLightningAddress: String? {
            let normalized = lightningAddress?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard let normalized, !normalized.isEmpty else { return nil }
            return normalized
        }

        var identityBindingPayload: MessagingIdentityBindingPayload? {
            guard let walletPubkey = walletPubkey?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !walletPubkey.isEmpty,
                  let lightningAddress = normalizedLightningAddress,
                  let messagingPubkey = messagingPubkey?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !messagingPubkey.isEmpty,
                  let messagingIdentitySignature = messagingIdentitySignature?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !messagingIdentitySignature.isEmpty,
                  let messagingIdentitySignatureVersion,
                  let messagingIdentitySignedAt
            else {
                return nil
            }

            return MessagingIdentityBindingPayload(
                walletPubkey: walletPubkey,
                lightningAddress: lightningAddress,
                messagingPubkey: messagingPubkey,
                messagingIdentitySignature: messagingIdentitySignature,
                messagingIdentitySignatureVersion: messagingIdentitySignatureVersion,
                messagingIdentitySignedAt: Int(messagingIdentitySignedAt.timeIntervalSince1970)
            )
        }
    }

    enum MessageKeyError: LocalizedError {
        case invalidURL
        case invalidStoredKey
        case invalidResponse
        case inactiveOnAnotherDevice
        case missingLightningAddress
        case serverError(statusCode: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid messaging key registration URL."
            case .invalidStoredKey:
                return "Stored messaging key is invalid."
            case .invalidResponse:
                return "Invalid messaging key registration response."
            case .inactiveOnAnotherDevice:
                return "Messaging is active on another device."
            case .missingLightningAddress:
                return "Create a Lightning Address before activating messaging."
            case .serverError(let statusCode, let message):
                return "Server error (\(statusCode)): \(message)"
            }
        }
    }

    private enum IdentityEndpoint {
        case legacyV1
        case v2
        case v3

        var path: String {
            switch self {
            case .legacyV1:
                return "/messaging-key"
            case .v2:
                return "/messaging/v2/identity"
            case .v3:
                return "/messaging/v3/identity"
            }
        }

        var signatureVersion: Int {
            switch self {
            case .legacyV1:
                return 1
            case .v2, .v3:
                return 2
            }
        }

        var enforcesInactiveDeviceCheck: Bool {
            self == .v2
        }

        var claimsActiveBinding: Bool {
            self == .v3
        }
    }

    private enum MessagingKeyVersion {
        case legacyV1
        case v2

        var baseKeychainKey: String {
            switch self {
            case .legacyV1:
                return "split.messaging.privateKey"
            case .v2:
                return "split.messaging.v2.privateKey"
            }
        }
    }

    private struct KeyState {
        let privateKey: Curve25519.KeyAgreement.PrivateKey
        let didCreate: Bool
    }

    private struct LocalIdentity {
        let walletPubkey: String
        let lightningAddress: String
        let messagingPubkey: String
    }

    private struct MessagingIdentityRegistrationRequest: Encodable {
        let walletPubkey: String
        let lightningAddress: String
        let messagingPubkey: String
        let messagingIdentitySignature: String
        let messagingIdentitySignatureVersion: Int
        let messagingIdentitySignedAt: Int
    }

    func ensureRegistered(
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> RegistrationResponse {
        let identityEndpoint: IdentityEndpoint = .v3

        try await authManager.ensureSession(walletManager: walletManager)

        let walletPubkey = try await currentWalletPubkey(walletManager: walletManager)
        guard let lightningAddress = try await fetchLocalLightningAddressWithRetry(
            walletManager: walletManager
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !lightningAddress.isEmpty else {
            throw MessageKeyError.missingLightningAddress
        }

        let v2KeyState = try loadOrCreatePrivateKey(for: .v2)

        let v2LocalIdentity = LocalIdentity(
            walletPubkey: walletPubkey,
            lightningAddress: lightningAddress,
            messagingPubkey: hexString(for: v2KeyState.privateKey.publicKey.rawRepresentation)
        )

        let v2Registration = try await ensureRegistration(
            for: identityEndpoint,
            localIdentity: v2LocalIdentity,
            keyState: v2KeyState,
            authManager: authManager,
            walletManager: walletManager
        )

        return v2Registration
    }

    func currentMessagingPublicKeyHex() throws -> String {
        let keyState = try loadOrCreatePrivateKey(for: .v2)
        return hexString(for: keyState.privateKey.publicKey.rawRepresentation)
    }

    func currentMessagingPrivateKey() throws -> Curve25519.KeyAgreement.PrivateKey {
        try loadOrCreatePrivateKey(for: .v2).privateKey
    }

    func messagingPrivateKey(
        forRecipientMessagingPubkey recipientMessagingPubkey: String
    ) throws -> Curve25519.KeyAgreement.PrivateKey {
        let normalizedRecipientMessagingPubkey = recipientMessagingPubkey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if let v2PrivateKey = try loadPrivateKeyIfPresent(for: .v2),
           hexString(for: v2PrivateKey.publicKey.rawRepresentation) == normalizedRecipientMessagingPubkey {
            return v2PrivateKey
        }

        if let legacyPrivateKey = try loadPrivateKeyIfPresent(for: .legacyV1),
           hexString(for: legacyPrivateKey.publicKey.rawRepresentation) == normalizedRecipientMessagingPubkey {
            return legacyPrivateKey
        }

        throw MessageKeyError.invalidStoredKey
    }

    func currentWalletPubkey(walletManager: WalletManager) async throws -> String {
        guard let sdk = walletManager.sdk else {
            throw AuthManager.AuthError.missingSigningProvider
        }

        let info = try await sdk.getInfo(request: GetInfoRequest(ensureSynced: false))
        return info.identityPubkey
    }

    func clearStoredMessagingKey() {
        KeychainHelper.delete(forKey: legacyMessagingPrivateKeyKeychainKey)
        allKeychainKeys(for: .v2).forEach { key in
            KeychainHelper.delete(forKey: key)
        }
        MessageDirectoryCheckpointStore.clear()
    }

    func shouldSilentlyDeferActivation(for error: Error) -> Bool {
        if let messageKeyError = error as? MessageKeyError {
            switch messageKeyError {
            case .missingLightningAddress, .inactiveOnAnotherDevice:
                return true
            default:
                return false
            }
        }

        let description = error.localizedDescription.lowercased()
        return description.contains("lightningaddress must exist before messaging can be activated") ||
            description.contains("messaging identity is not registered") ||
            description.contains("messaging key is not registered") ||
            description.contains("messaging is active on another device")
    }

    func buildMessagingIdentityBindingMessage(
        version: Int,
        walletPubkey: String,
        lightningAddress: String,
        messagingPubkey: String,
        signedAt: Int
    ) -> String {
        """
        SplitRewards Messaging Identity Authorization
        version=\(version)
        domain=\(messagingIdentityDomain)
        walletPubkey=\(walletPubkey)
        lightningAddress=\(lightningAddress)
        messagingPubkey=\(messagingPubkey)
        signedAt=\(signedAt)
        """
    }

    private func ensureRegistration(
        for endpoint: IdentityEndpoint,
        localIdentity: LocalIdentity,
        keyState: KeyState,
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> RegistrationResponse {
        var localIdentity = localIdentity
        var keyState = keyState
        let current = try await fetchCurrentRegistration(
            for: endpoint,
            authManager: authManager,
            walletManager: walletManager
        )

        if isRegistrationValid(
            current,
            for: endpoint,
            localIdentity: localIdentity
        ) {
            return current
        }

        if endpoint.enforcesInactiveDeviceCheck,
           let currentMessagingPubkey = current.messagingPubkey?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           !currentMessagingPubkey.isEmpty,
           currentMessagingPubkey != localIdentity.messagingPubkey,
           !keyState.didCreate {
            throw MessageKeyError.inactiveOnAnotherDevice
        }

        if endpoint.claimsActiveBinding,
           let currentMessagingPubkey = current.messagingPubkey?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           !currentMessagingPubkey.isEmpty,
           currentMessagingPubkey != localIdentity.messagingPubkey {
            let rotatedPrivateKey = Curve25519.KeyAgreement.PrivateKey()
            savePrivateKey(rotatedPrivateKey, for: .v2)
            keyState = KeyState(privateKey: rotatedPrivateKey, didCreate: true)
            localIdentity = LocalIdentity(
                walletPubkey: localIdentity.walletPubkey,
                lightningAddress: localIdentity.lightningAddress,
                messagingPubkey: hexString(for: rotatedPrivateKey.publicKey.rawRepresentation)
            )
        }

        let signedAt = Int(Date().timeIntervalSince1970)
        let canonicalMessage = buildMessagingIdentityBindingMessage(
            version: endpoint.signatureVersion,
            walletPubkey: localIdentity.walletPubkey,
            lightningAddress: localIdentity.lightningAddress,
            messagingPubkey: localIdentity.messagingPubkey,
            signedAt: signedAt
        )
        let signed = try await walletManager.signAuthMessage(canonicalMessage)

        let normalizedSignedWalletPubkey = signed.pubkey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalizedSignedWalletPubkey != localIdentity.walletPubkey.lowercased() {
            throw MessageKeyError.invalidResponse
        }

        let response = try await postRegistration(
            to: endpoint,
            requestBody: MessagingIdentityRegistrationRequest(
                walletPubkey: signed.pubkey,
                lightningAddress: localIdentity.lightningAddress,
                messagingPubkey: localIdentity.messagingPubkey,
                messagingIdentitySignature: signed.signature,
                messagingIdentitySignatureVersion: endpoint.signatureVersion,
                messagingIdentitySignedAt: signedAt
            ),
            authManager: authManager,
            walletManager: walletManager
        )

        guard isRegistrationValid(
            response,
            for: endpoint,
            localIdentity: localIdentity
        ) else {
            throw MessageKeyError.invalidResponse
        }

        return response
    }

    private func fetchCurrentRegistration(
        for endpoint: IdentityEndpoint,
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> RegistrationResponse {
        guard let url = URL(string: "\(AppConfig.baseURL)\(endpoint.path)") else {
            throw MessageKeyError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = true
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse,
           http.statusCode == 401 || http.statusCode == 403 {
            authManager.invalidateSession()
            try await authManager.ensureSession(walletManager: walletManager)
            (data, response) = try await URLSession.shared.data(for: request)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw MessageKeyError.invalidResponse
        }

        do {
            return try registrationDecoder().decode(RegistrationResponse.self, from: data)
        } catch {
            throw MessageKeyError.invalidResponse
        }
    }

    private func postRegistration(
        to endpoint: IdentityEndpoint,
        requestBody: MessagingIdentityRegistrationRequest,
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> RegistrationResponse {
        guard let url = URL(string: "\(AppConfig.baseURL)\(endpoint.path)") else {
            throw MessageKeyError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(requestBody)

        var (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse,
           http.statusCode == 401 || http.statusCode == 403 {
            authManager.invalidateSession()
            try await authManager.ensureSession(walletManager: walletManager)
            (data, response) = try await URLSession.shared.data(for: request)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MessageKeyError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let serverMessage: String

            if let decoded = try? registrationDecoder().decode(RegistrationResponse.self, from: data),
               let error = decoded.error,
               !error.isEmpty {
                serverMessage = error
            } else {
                serverMessage = String(data: data, encoding: .utf8) ?? "Unknown server error"
            }

            throw MessageKeyError.serverError(
                statusCode: httpResponse.statusCode,
                message: serverMessage
            )
        }

        do {
            return try registrationDecoder().decode(RegistrationResponse.self, from: data)
        } catch {
            throw MessageKeyError.invalidResponse
        }
    }

    private func isRegistrationValid(
        _ response: RegistrationResponse,
        for endpoint: IdentityEndpoint,
        localIdentity: LocalIdentity
    ) -> Bool {
        guard let binding = response.identityBindingPayload,
              binding.messagingIdentitySignatureVersion == endpoint.signatureVersion,
              binding.walletPubkey.lowercased() == localIdentity.walletPubkey.lowercased(),
              binding.lightningAddress == localIdentity.lightningAddress,
              binding.messagingPubkey == localIdentity.messagingPubkey
        else {
            return false
        }

        do {
            try MessageKeyBindingVerifier.verifyBinding(binding)
            if endpoint == .v2 {
                guard let directory = response.directory else {
                    return false
                }

                try MessagingDirectoryVerifier.verifyDirectoryProof(
                    binding: binding,
                    directory: directory
                )
                try MessageDirectoryCheckpointStore.storeIfNewer(directory.checkpoint)
            }
            return true
        } catch {
            return false
        }
    }

    private func fetchLocalLightningAddressWithRetry(
        walletManager: WalletManager
    ) async throws -> String? {
        var lastResult: String?

        for attempt in 1...lightningAddressLookupMaxAttempts {
            lastResult = try await walletManager.fetchLightningAddress()?.lightningAddress

            if let lastResult,
               !lastResult.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return lastResult
            }

            if let cachedLightningAddress = walletManager.cachedLightningAddress(),
               !cachedLightningAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return cachedLightningAddress
            }

            guard attempt < lightningAddressLookupMaxAttempts else {
                break
            }

            try? await Task.sleep(nanoseconds: lightningAddressLookupRetryDelayNanoseconds)
        }

        return lastResult
    }

    private func registrationDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            let fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            if let date = fractionalFormatter.date(from: value) {
                return date
            }

            let standardFormatter = ISO8601DateFormatter()
            standardFormatter.formatOptions = [.withInternetDateTime]

            if let date = standardFormatter.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date: \(value)"
            )
        }
        return decoder
    }

    private func loadPrivateKeyIfPresent(
        for version: MessagingKeyVersion
    ) throws -> Curve25519.KeyAgreement.PrivateKey? {
        let preferredKey = preferredKeychainKey(for: version)

        for key in readableKeychainKeys(for: version) {
            guard let stored = KeychainHelper.read(forKey: key) else {
                continue
            }

            let privateKey: Curve25519.KeyAgreement.PrivateKey
            do {
                privateKey = try decodePrivateKey(from: stored)
            } catch {
                KeychainHelper.delete(forKey: key)
                continue
            }

            if key != preferredKey,
               KeychainHelper.read(forKey: preferredKey) == nil {
                KeychainHelper.save(stored, forKey: preferredKey)
            }

            return privateKey
        }

        return nil
    }

    private func decodePrivateKey(
        from stored: String
    ) throws -> Curve25519.KeyAgreement.PrivateKey {
        guard let data = Data(base64Encoded: stored) else {
            throw MessageKeyError.invalidStoredKey
        }

        do {
            return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
        } catch {
            throw MessageKeyError.invalidStoredKey
        }
    }

    private func preferredKeychainKey(for version: MessagingKeyVersion) -> String {
        switch version {
        case .legacyV1:
            return version.baseKeychainKey
        case .v2:
            return "\(messagingV2PrivateKeyKeychainKeyBase).\(AppConfig.messagingPushEnvironment)"
        }
    }

    private func readableKeychainKeys(for version: MessagingKeyVersion) -> [String] {
        let preferredKey = preferredKeychainKey(for: version)

        switch version {
        case .legacyV1:
            return [preferredKey]
        case .v2:
            return [preferredKey, version.baseKeychainKey]
        }
    }

    private func allKeychainKeys(for version: MessagingKeyVersion) -> [String] {
        switch version {
        case .legacyV1:
            return [version.baseKeychainKey]
        case .v2:
            return [
                version.baseKeychainKey,
                "\(messagingV2PrivateKeyKeychainKeyBase).dev",
                "\(messagingV2PrivateKeyKeychainKeyBase).prod"
            ]
        }
    }

    private func savePrivateKey(
        _ privateKey: Curve25519.KeyAgreement.PrivateKey,
        for version: MessagingKeyVersion
    ) {
        let encoded = privateKey.rawRepresentation.base64EncodedString()
        KeychainHelper.save(encoded, forKey: preferredKeychainKey(for: version))
    }

    private func loadOrCreatePrivateKey(for version: MessagingKeyVersion) throws -> KeyState {
        if let privateKey = try loadPrivateKeyIfPresent(for: version) {
            return KeyState(privateKey: privateKey, didCreate: false)
        }

        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        savePrivateKey(privateKey, for: version)
        return KeyState(privateKey: privateKey, didCreate: true)
    }

    private func hexString(for data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
