//
//  ShareExtensionMessagingRuntime.swift
//  Split Share Extension
//
//

import BreezSdkSpark
import CryptoKit
import Foundation
import Security
import UIKit
import secp256k1

private struct ShareExtensionAppConfig {
    static let baseURL: String = {
        guard let rawScheme = Bundle.main.object(forInfoDictionaryKey: "SplitBaseScheme") as? String else {
            preconditionFailure("SplitBaseScheme is missing from the share extension configuration.")
        }

        guard let rawHost = Bundle.main.object(forInfoDictionaryKey: "SplitBaseHost") as? String else {
            preconditionFailure("SplitBaseHost is missing from the share extension configuration.")
        }

        let scheme = rawScheme.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !scheme.isEmpty, !host.isEmpty else {
            preconditionFailure("Split base URL config is empty.")
        }

        let value = "\(scheme)://\(host)"
        guard URL(string: value) != nil else {
            preconditionFailure("Split base URL config is invalid.")
        }

        return value
    }()

    static let messagingPushEnvironment: String = {
        let configuredValue = (Bundle.main.object(forInfoDictionaryKey: "SplitMessagingPushEnvironment") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if let configuredValue, ["dev", "prod"].contains(configuredValue) {
            return configuredValue
        }

        guard let url = URL(string: baseURL),
              let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return "prod"
        }

        if host == "localhost" || host.hasSuffix(".local") || host.contains("dev") || host.contains("ngrok") {
            return "dev"
        }

        return "prod"
    }()

    static let sharedAppGroupIdentifier = requiredConfigValue("SplitAppGroupIdentifier")
    static let sharedKeychainAccessGroup = requiredConfigValue("SplitSharedKeychainAccessGroup")
    static let keychainService = requiredConfigValue("SplitKeychainService")
    static let messagingIdentityDomain = requiredConfigValue("SplitMessagingIdentityDomain")
    static let lightningAddressDomain = requiredConfigValue("SplitLightningAddressDomain")

    private static func requiredConfigValue(_ key: String) -> String {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            preconditionFailure("\(key) is missing from the share extension configuration.")
        }

        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            preconditionFailure("\(key) is empty in the share extension configuration.")
        }

        return value
    }
}

private struct ShareExtensionKeychainHelper {
    static let walletSeedKey = "split.wallet.seed"

    private static let service = ShareExtensionAppConfig.keychainService
    private static let sharedAccessGroup = ShareExtensionAppConfig.sharedKeychainAccessGroup

    static func save(_ value: String, forKey key: String) {
        delete(forKey: key)

        if !replaceValue(value, forKey: key, accessGroup: sharedAccessGroup) {
            _ = replaceValue(value, forKey: key, accessGroup: nil)
        }
    }

    static func read(forKey key: String) -> String? {
        if let value = readValue(forKey: key, accessGroup: sharedAccessGroup) {
            return value
        }

        if let legacyValue = readValue(forKey: key, accessGroup: nil) {
            let migratedToSharedGroup = replaceValue(
                legacyValue,
                forKey: key,
                accessGroup: sharedAccessGroup
            )

            if migratedToSharedGroup,
               readValue(forKey: key, accessGroup: sharedAccessGroup) == legacyValue {
                deleteLegacyOnly(forKey: key)
            }

            return legacyValue
        }

        return nil
    }

    static func delete(forKey key: String) {
        SecItemDelete(query(forKey: key, accessGroup: sharedAccessGroup) as CFDictionary)
        SecItemDelete(query(forKey: key, accessGroup: nil) as CFDictionary)
    }

    private static func deleteLegacyOnly(forKey key: String) {
        SecItemDelete(query(forKey: key, accessGroup: nil) as CFDictionary)
    }

    private static func readValue(forKey key: String, accessGroup: String?) -> String? {
        var result: AnyObject?
        let status = SecItemCopyMatching(
            readQuery(forKey: key, accessGroup: accessGroup) as CFDictionary,
            &result
        )

        guard status == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8) else {
            return nil
        }

        return str
    }

    @discardableResult
    private static func replaceValue(forKey key: String, data: Data, accessGroup: String?) -> Bool {
        SecItemDelete(query(forKey: key, accessGroup: accessGroup) as CFDictionary)

        let status = SecItemAdd(
            addQuery(forKey: key, data: data, accessGroup: accessGroup) as CFDictionary,
            nil
        )

        return status == errSecSuccess
    }

    @discardableResult
    private static func replaceValue(_ value: String, forKey key: String, accessGroup: String?) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        return replaceValue(forKey: key, data: data, accessGroup: accessGroup)
    }

    private static func query(forKey key: String, accessGroup: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        return query
    }

    private static func readQuery(forKey key: String, accessGroup: String?) -> [String: Any] {
        var query = query(forKey: key, accessGroup: accessGroup)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }

    private static func addQuery(forKey key: String, data: Data, accessGroup: String?) -> [String: Any] {
        var query = query(forKey: key, accessGroup: accessGroup)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return query
    }
}

private struct ShareExtensionMessagingIdentityBindingPayload: Codable, Hashable {
    let walletPubkey: String
    let lightningAddress: String
    let messagingPubkey: String
    let messagingIdentitySignature: String
    let messagingIdentitySignatureVersion: Int
    let messagingIdentitySignedAt: Int
}

private struct ShareExtensionMessagingRecipient: Codable, Hashable {
    let walletPubkey: String
    let lightningAddress: String
    let messagingPubkey: String
    let messagingIdentitySignature: String
    let messagingIdentitySignatureVersion: Int
    let messagingIdentitySignedAt: Date
    let profilePicUrl: String?

    var identityBindingPayload: ShareExtensionMessagingIdentityBindingPayload {
        ShareExtensionMessagingIdentityBindingPayload(
            walletPubkey: walletPubkey,
            lightningAddress: lightningAddress
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
            messagingPubkey: messagingPubkey,
            messagingIdentitySignature: messagingIdentitySignature,
            messagingIdentitySignatureVersion: messagingIdentitySignatureVersion,
            messagingIdentitySignedAt: Int(messagingIdentitySignedAt.timeIntervalSince1970)
        )
    }
}

private struct ShareExtensionMessagingDirectoryCheckpoint: Codable, Hashable {
    let rootHash: String
    let treeSize: Int
    let issuedAt: Date
}

private struct ShareExtensionMessagingDirectoryProofNode: Codable, Hashable {
    let position: String
    let hash: String
}

private struct ShareExtensionMessagingDirectoryProofPayload: Codable, Hashable {
    let leafIndex: Int
    let leafHash: String
    let proof: [ShareExtensionMessagingDirectoryProofNode]
    let checkpoint: ShareExtensionMessagingDirectoryCheckpoint
}

private struct ShareExtensionRegistrationResponse: Decodable {
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
    let directory: ShareExtensionMessagingDirectoryProofPayload?
    let error: String?

    var normalizedLightningAddress: String? {
        let normalized = lightningAddress?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let normalized, !normalized.isEmpty else { return nil }
        return normalized
    }

    var identityBindingPayload: ShareExtensionMessagingIdentityBindingPayload? {
        guard let walletPubkey = walletPubkey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !walletPubkey.isEmpty,
              let lightningAddress = normalizedLightningAddress,
              let messagingPubkey = messagingPubkey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !messagingPubkey.isEmpty,
              let messagingIdentitySignature = messagingIdentitySignature?.trimmingCharacters(in: .whitespacesAndNewlines),
              !messagingIdentitySignature.isEmpty,
              let messagingIdentitySignatureVersion,
              let messagingIdentitySignedAt else {
            return nil
        }

        return ShareExtensionMessagingIdentityBindingPayload(
            walletPubkey: walletPubkey,
            lightningAddress: lightningAddress,
            messagingPubkey: messagingPubkey,
            messagingIdentitySignature: messagingIdentitySignature,
            messagingIdentitySignatureVersion: messagingIdentitySignatureVersion,
            messagingIdentitySignedAt: Int(messagingIdentitySignedAt.timeIntervalSince1970)
        )
    }
}

private struct ShareExtensionResolveRecipientResponse: Decodable {
    let ok: Bool
    let recipient: ShareExtensionMessagingRecipient
    let directory: ShareExtensionMessagingDirectoryProofPayload
}

private struct ShareExtensionSendMessageEnvelope {
    let clientMessageId: String
    let recipient: ShareExtensionMessagingIdentityBindingPayload
    let ciphertext: String
    let nonce: String
    let senderEphemeralPubkey: String
    let createdAtClientMs: Int64
    let envelopeVersion: Int
    let messageType: String
    let attachmentIds: [String]?
}

private struct ShareExtensionSendMessageResponse: Decodable {
    let ok: Bool
    let message: ShareExtensionSentRelayMessage?
    let deduped: Bool?
}

private struct ShareExtensionSentRelayMessage: Decodable {
    let messageId: String
    let clientMessageId: String
    let recipientWalletPubkey: String
    let recipientMessagingPubkey: String
    let recipientLightningAddress: String
    let status: String
    let createdAt: Date?
    let createdAtClient: Date?
}

private struct ShareExtensionAttachmentUploadResponse: Decodable {
    let ok: Bool
    let attachment: ShareExtensionMessagingAttachmentRecord
}

private struct ShareExtensionMessagingAttachmentRecord: Decodable {
    let attachmentId: String
    let recipientLightningAddress: String
    let sizeBytes: Int
    let uploadContentType: String
    let status: String
}

private struct ShareExtensionAttachmentMessagePayload: Codable, Equatable {
    let attachmentId: String
    let fileName: String
    let mimeType: String
    let sizeBytes: Int
    let imageWidth: Int?
    let imageHeight: Int?
    let attachmentNonce: String
    let attachmentSenderEphemeralPubkey: String
}

private struct ShareExtensionSealedSenderMessagePayload: Codable {
    let body: String
    let sender: ShareExtensionMessagingIdentityBindingPayload
    let senderEnvelopeSignature: String
    let senderEnvelopeSignatureVersion: Int
}

private struct ShareExtensionSendEnvelopePayload {
    let ciphertext: String
    let nonce: String
    let senderEphemeralPubkey: String
    let envelopeVersion: Int
}

private struct ShareExtensionEncryptedAttachmentPayload {
    let ciphertext: Data
    let nonce: String
    let senderEphemeralPubkey: String
}

private struct ShareExtensionEncryptedBinaryPayload {
    let ciphertext: Data
    let nonce: Data
    let senderEphemeralPubkey: String
}

private struct ShareExtensionOutgoingMessageRelayRecord: Codable {
    let id: String
    let conversationId: String
    let clientMessageId: String
    let body: String
    let createdAt: Date
    let senderWalletPubkey: String
    let senderMessagingPubkey: String
    let senderLightningAddress: String?
    let recipientWalletPubkey: String
    let recipientMessagingPubkey: String
    let recipientLightningAddress: String
    let messageType: String
}

private enum ShareExtensionOutgoingMessageRelayStore {
    private static let defaultsKey = "shareExtensionOutgoingMessageRelayRecords"

    static func enqueue(_ record: ShareExtensionOutgoingMessageRelayRecord) {
        guard let defaults = UserDefaults(suiteName: ShareMessageExtensionStorage.appGroupIdentifier) else {
            return
        }

        let existingRecords: [ShareExtensionOutgoingMessageRelayRecord]
        if let encoded = defaults.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([ShareExtensionOutgoingMessageRelayRecord].self, from: encoded) {
            existingRecords = decoded
        } else {
            existingRecords = []
        }

        var mergedByClientMessageId = Dictionary(uniqueKeysWithValues: existingRecords.map { ($0.clientMessageId, $0) })
        mergedByClientMessageId[record.clientMessageId] = record

        let records = mergedByClientMessageId.values.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id < rhs.id
            }
            return lhs.createdAt < rhs.createdAt
        }

        if let encoded = try? JSONEncoder().encode(records) {
            defaults.set(encoded, forKey: defaultsKey)
        }
    }
}

private enum ShareExtensionMessagingError: LocalizedError {
    case missingWalletSeed
    case missingLightningAddress
    case inactiveOnAnotherDevice
    case recipientBindingStale
    case invalidRecipient
    case missingSharedFile
    case attachmentTooLarge(maxBytes: Int)
    case invalidStoredKey
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingWalletSeed:
            return "This device needs a Split wallet before the share extension can send messages."
        case .missingLightningAddress:
            return "Create a Lightning Address in Split before using direct share-to-message."
        case .inactiveOnAnotherDevice:
            return "Messaging is active on another device. Open Split on this phone first to reactivate it here."
        case .recipientBindingStale:
            return "The recipient messaging identity changed. Please try sending again."
        case .invalidRecipient:
            return "Enter a valid Lightning Address."
        case .missingSharedFile:
            return "The shared attachment is no longer available."
        case .attachmentTooLarge(let maxBytes):
            return "Attachments must be smaller than \(ByteCountFormatter.string(fromByteCount: Int64(maxBytes), countStyle: .file))."
        case .invalidStoredKey:
            return "The stored messaging identity is invalid."
        case .invalidResponse:
            return "The server response was invalid."
        }
    }
}

private enum ShareExtensionMessageRecipientTrustStore {
    enum TrustError: LocalizedError {
        case invalidLightningAddress
        case conflictingWallet(lightningAddress: String, expectedWalletPubkey: String, receivedWalletPubkey: String)

        var errorDescription: String? {
            switch self {
            case .invalidLightningAddress:
                return "The recipient Lightning address is invalid."
            case .conflictingWallet(let lightningAddress, _, _):
                return "This Lightning address no longer matches the wallet you previously verified: \(lightningAddress)"
            }
        }
    }

    private static let pinnedRecipientsDefaultsKey = "split.messaging.trustedRecipientsByLightningAddress"

    static func enforceOrPin(_ binding: ShareExtensionMessagingIdentityBindingPayload) throws {
        let normalizedLightningAddress = try normalizeLightningAddress(binding.lightningAddress)
        let normalizedWalletPubkey = binding.walletPubkey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalizedWalletPubkey.isEmpty else {
            throw TrustError.invalidLightningAddress
        }

        var pinnedRecipients = UserDefaults.standard.dictionary(
            forKey: pinnedRecipientsDefaultsKey
        ) as? [String: String] ?? [:]

        if let existingWalletPubkey = pinnedRecipients[normalizedLightningAddress],
           existingWalletPubkey.lowercased() != normalizedWalletPubkey {
            throw TrustError.conflictingWallet(
                lightningAddress: normalizedLightningAddress,
                expectedWalletPubkey: existingWalletPubkey,
                receivedWalletPubkey: normalizedWalletPubkey
            )
        }

        if pinnedRecipients[normalizedLightningAddress] == nil {
            pinnedRecipients[normalizedLightningAddress] = normalizedWalletPubkey
            UserDefaults.standard.set(pinnedRecipients, forKey: pinnedRecipientsDefaultsKey)
        }
    }

    private static func normalizeLightningAddress(_ value: String) throws -> String {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard normalized.contains("@"), !normalized.isEmpty else {
            throw TrustError.invalidLightningAddress
        }

        return normalized
    }
}

private enum ShareExtensionMessageDirectoryCheckpointStore {
    enum CheckpointError: LocalizedError {
        case staleCheckpoint
        case conflictingCheckpoint

        var errorDescription: String? {
            switch self {
            case .staleCheckpoint:
                return "The messaging directory checkpoint is stale."
            case .conflictingCheckpoint:
                return "The messaging directory checkpoint conflicts with a previously stored checkpoint."
            }
        }
    }

    private static let legacyDefaultsKey = "split.messaging.directoryCheckpoint"
    private static let defaultsKeyPrefix = "split.messaging.directoryCheckpoint."

    static func storeIfNewer(
        _ checkpoint: ShareExtensionMessagingDirectoryCheckpoint,
        scope: String = ShareExtensionAppConfig.baseURL
    ) throws {
        let defaults = UserDefaults.standard
        removeLegacyCheckpointIfPresent(from: defaults)
        let defaultsKey = scopedDefaultsKey(for: scope)

        if let existingData = defaults.data(forKey: defaultsKey),
           let existing = try? JSONDecoder().decode(ShareExtensionMessagingDirectoryCheckpoint.self, from: existingData) {
            if checkpoint.treeSize < existing.treeSize {
                throw CheckpointError.staleCheckpoint
            }

            if checkpoint.treeSize == existing.treeSize,
               checkpoint.rootHash.lowercased() != existing.rootHash.lowercased() {
                throw CheckpointError.conflictingCheckpoint
            }

            if checkpoint.treeSize == existing.treeSize {
                return
            }
        }

        let data = try JSONEncoder().encode(checkpoint)
        defaults.set(data, forKey: defaultsKey)
    }

    private static func scopedDefaultsKey(for scope: String) -> String {
        let normalizedScope = scope
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalizedScope.isEmpty else {
            return "\(defaultsKeyPrefix)default"
        }

        return defaultsKeyPrefix + normalizedScope
    }

    private static func removeLegacyCheckpointIfPresent(from defaults: UserDefaults) {
        if defaults.object(forKey: legacyDefaultsKey) != nil {
            defaults.removeObject(forKey: legacyDefaultsKey)
        }
    }
}

private enum ShareExtensionMessageKeyBindingVerifier {
    private static let supportedSignatureVersions: Set<Int> = [1, 2]
    private static let messagingIdentityDomain = ShareExtensionAppConfig.messagingIdentityDomain

    enum VerificationError: LocalizedError {
        case missingBinding
        case unsupportedSignatureVersion
        case invalidWalletPubkey
        case invalidSignatureEncoding
        case invalidSignature

        var errorDescription: String? {
            switch self {
            case .missingBinding:
                return "Recipient messaging identity is incomplete."
            case .unsupportedSignatureVersion:
                return "Unsupported messaging identity signature version."
            case .invalidWalletPubkey:
                return "Recipient wallet pubkey is invalid."
            case .invalidSignatureEncoding:
                return "Recipient messaging identity signature format is invalid."
            case .invalidSignature:
                return "Recipient messaging identity signature could not be verified."
            }
        }
    }

    static func verifyBinding(_ binding: ShareExtensionMessagingIdentityBindingPayload) throws {
        guard supportedSignatureVersions.contains(binding.messagingIdentitySignatureVersion) else {
            throw VerificationError.unsupportedSignatureVersion
        }

        let canonicalMessage = buildMessagingIdentityBindingMessage(
            version: binding.messagingIdentitySignatureVersion,
            walletPubkey: binding.walletPubkey,
            lightningAddress: binding.lightningAddress,
            messagingPubkey: binding.messagingPubkey,
            signedAt: binding.messagingIdentitySignedAt
        )

        try verifySignedMessage(
            canonicalMessage,
            signatureHex: binding.messagingIdentitySignature,
            walletPubkey: binding.walletPubkey,
            invalidSignatureError: .invalidSignature
        )
    }

    static func buildMessagingIdentityBindingMessage(
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

    static func buildDirectoryLeafMessage(_ binding: ShareExtensionMessagingIdentityBindingPayload) -> String {
        """
        SplitRewards Messaging Directory Leaf
        version=\(binding.messagingIdentitySignatureVersion)
        walletPubkey=\(binding.walletPubkey)
        lightningAddress=\(binding.lightningAddress)
        messagingPubkey=\(binding.messagingPubkey)
        signature=\(binding.messagingIdentitySignature)
        signedAt=\(binding.messagingIdentitySignedAt)
        """
    }

    static func buildMessagingEnvelopeSignatureMessage(
        version: Int,
        clientMessageId: String,
        senderBinding: ShareExtensionMessagingIdentityBindingPayload,
        recipientWalletPubkey: String,
        recipientLightningAddress: String,
        recipientMessagingPubkey: String,
        messageType: String,
        plaintext: String,
        createdAtClientMs: Int64,
        envelopeVersion: Int
    ) -> String {
        """
        SplitRewards Messaging Envelope Authorization
        version=\(version)
        domain=\(messagingIdentityDomain)
        clientMessageId=\(clientMessageId)
        senderWalletPubkey=\(senderBinding.walletPubkey)
        senderLightningAddress=\(senderBinding.lightningAddress)
        senderMessagingPubkey=\(senderBinding.messagingPubkey)
        recipientWalletPubkey=\(recipientWalletPubkey)
        recipientLightningAddress=\(recipientLightningAddress)
        recipientMessagingPubkey=\(recipientMessagingPubkey)
        messageType=\(messageType)
        plaintext=\(plaintext)
        createdAtClientMs=\(createdAtClientMs)
        envelopeVersion=\(envelopeVersion)
        """
    }

    private static func compactSignatureCandidates(from signatureHex: String) throws -> [[UInt8]] {
        guard let signatureData = strictHexData(signatureHex) else {
            throw VerificationError.invalidSignatureEncoding
        }

        switch signatureData.count {
        case 64:
            return [Array(signatureData)]
        case 65:
            return [
                Array(signatureData.prefix(64)),
                Array(signatureData.dropFirst()),
            ]
        default:
            throw VerificationError.invalidSignatureEncoding
        }
    }

    private static func normalizedWalletPubkeyBytes(_ hex: String) -> [UInt8]? {
        guard let normalizedHex = normalizeWalletPubkeyHex(hex) else {
            return nil
        }

        return [UInt8](Data(hex: normalizedHex))
    }

    private static func normalizeWalletPubkeyHex(_ hex: String) -> String? {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("0x") || value.hasPrefix("0X") {
            value.removeFirst(2)
        }

        guard value.allSatisfy(\.isHexDigit) else {
            return nil
        }

        let lowercased = value.lowercased()
        if lowercased.count == 66 || lowercased.count == 130 {
            return lowercased
        }

        if lowercased.count == 128 {
            return "04" + lowercased
        }

        return nil
    }

    private static func strictHexData(_ hex: String) -> Data? {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("0x") || value.hasPrefix("0X") {
            value.removeFirst(2)
        }

        guard !value.isEmpty, value.count.isMultiple(of: 2), value.allSatisfy(\.isHexDigit) else {
            return nil
        }

        return Data(hex: value)
    }

    private static func verifySignedMessage(
        _ canonicalMessage: String,
        signatureHex: String,
        walletPubkey: String,
        invalidSignatureError: VerificationError
    ) throws {
        guard let pubkeyBytes = normalizedWalletPubkeyBytes(walletPubkey) else {
            throw VerificationError.invalidWalletPubkey
        }

        let messageDigest = Array(SHA256.hash(data: Data(canonicalMessage.utf8)))
        let signatureCandidates = try compactSignatureCandidates(from: signatureHex)
        let isValid = signatureCandidates.contains { signatureBytes in
            verifyCompactSignature(
                signatureBytes: signatureBytes,
                digestBytes: messageDigest,
                pubkeyBytes: pubkeyBytes
            )
        }

        if !isValid {
            throw invalidSignatureError
        }
    }

    private static func verifyCompactSignature(
        signatureBytes: [UInt8],
        digestBytes: [UInt8],
        pubkeyBytes: [UInt8]
    ) -> Bool {
        guard signatureBytes.count == 64 else {
            return false
        }

        var parsedSignature = secp256k1_ecdsa_signature()
        var parsedPublicKey = secp256k1_pubkey()

        return secp256k1_ecdsa_signature_parse_compact(
            secp256k1.Context.raw,
            &parsedSignature,
            signatureBytes
        ) != 0 &&
        secp256k1_ec_pubkey_parse(
            secp256k1.Context.raw,
            &parsedPublicKey,
            pubkeyBytes,
            pubkeyBytes.count
        ) != 0 &&
        secp256k1_ecdsa_verify(
            secp256k1.Context.raw,
            &parsedSignature,
            digestBytes,
            &parsedPublicKey
        ) != 0
    }
}

private enum ShareExtensionMessagingDirectoryVerifier {
    enum VerificationError: LocalizedError {
        case invalidLeafHash
        case invalidProofHash
        case invalidProofPosition
        case invalidRootHash

        var errorDescription: String? {
            switch self {
            case .invalidLeafHash:
                return "The messaging directory leaf hash is invalid."
            case .invalidProofHash:
                return "The messaging directory proof is invalid."
            case .invalidProofPosition:
                return "The messaging directory proof position is invalid."
            case .invalidRootHash:
                return "The messaging directory root hash does not match the binding proof."
            }
        }
    }

    static func verifyDirectoryProof(
        binding: ShareExtensionMessagingIdentityBindingPayload,
        directory: ShareExtensionMessagingDirectoryProofPayload
    ) throws {
        let computedLeafHash = try sha256Hex(ShareExtensionMessageKeyBindingVerifier.buildDirectoryLeafMessage(binding))
        guard computedLeafHash == normalizedHex(directory.leafHash) else {
            throw VerificationError.invalidLeafHash
        }

        var cursorHash = computedLeafHash
        for node in directory.proof {
            let siblingHash = normalizedHex(node.hash)
            switch node.position.lowercased() {
            case "left":
                cursorHash = try sha256HexPair(leftHex: siblingHash, rightHex: cursorHash)
            case "right":
                cursorHash = try sha256HexPair(leftHex: cursorHash, rightHex: siblingHash)
            default:
                throw VerificationError.invalidProofPosition
            }
        }

        guard cursorHash == normalizedHex(directory.checkpoint.rootHash) else {
            throw VerificationError.invalidRootHash
        }
    }

    private static func sha256Hex(_ value: String) throws -> String {
        guard let data = value.data(using: .utf8) else {
            throw VerificationError.invalidLeafHash
        }

        return Data(SHA256.hash(data: data)).hexString
    }

    private static func sha256HexPair(leftHex: String, rightHex: String) throws -> String {
        let left = try strictHexData(leftHex)
        let right = try strictHexData(rightHex)
        var combined = Data()
        combined.append(left)
        combined.append(right)
        return Data(SHA256.hash(data: combined)).hexString
    }

    private static func strictHexData(_ hex: String) throws -> Data {
        let normalized = normalizedHex(hex)
        guard normalized.count == 64 else {
            throw VerificationError.invalidProofHash
        }

        var data = Data(capacity: normalized.count / 2)
        var index = normalized.startIndex

        while index < normalized.endIndex {
            let next = normalized.index(index, offsetBy: 2)
            let byteString = normalized[index..<next]
            guard let byte = UInt8(byteString, radix: 16) else {
                throw VerificationError.invalidProofHash
            }
            data.append(byte)
            index = next
        }

        return data
    }

    private static func normalizedHex(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

private enum ShareExtensionMessagePayloadCodec {
    private static let encoder = JSONEncoder()

    static func encodeAttachment(_ payload: ShareExtensionAttachmentMessagePayload) throws -> String {
        let data = try encoder.encode(payload)
        guard let string = String(data: data, encoding: .utf8) else {
            throw ShareExtensionMessagingError.invalidResponse
        }
        return string
    }
}

private enum ShareExtensionMessageCrypto {
    enum CryptoError: LocalizedError {
        case invalidPlaintext
        case invalidRecipientPublicKey
        case invalidCiphertext

        var errorDescription: String? {
            switch self {
            case .invalidPlaintext:
                return "The message text is invalid."
            case .invalidRecipientPublicKey:
                return "The recipient messaging public key is invalid."
            case .invalidCiphertext:
                return "The encrypted attachment could not be prepared."
            }
        }
    }

    static func encrypt(
        plaintext: String,
        recipientMessagingPubkeyHex: String
    ) throws -> ShareExtensionSendEnvelopePayload {
        guard let plaintextData = plaintext.data(using: .utf8) else {
            throw CryptoError.invalidPlaintext
        }

        let encryptedPayload = try encryptPayload(
            plaintextData: plaintextData,
            recipientMessagingPubkeyHex: recipientMessagingPubkeyHex
        )

        return ShareExtensionSendEnvelopePayload(
            ciphertext: encryptedPayload.ciphertext.base64EncodedString(),
            nonce: encryptedPayload.nonce.base64EncodedString(),
            senderEphemeralPubkey: encryptedPayload.senderEphemeralPubkey,
            envelopeVersion: 3
        )
    }

    static func encryptAttachmentData(
        _ data: Data,
        recipientMessagingPubkeyHex: String
    ) throws -> ShareExtensionEncryptedAttachmentPayload {
        let encryptedPayload = try encryptPayload(
            plaintextData: data,
            recipientMessagingPubkeyHex: recipientMessagingPubkeyHex
        )

        return ShareExtensionEncryptedAttachmentPayload(
            ciphertext: encryptedPayload.ciphertext,
            nonce: encryptedPayload.nonce.base64EncodedString(),
            senderEphemeralPubkey: encryptedPayload.senderEphemeralPubkey
        )
    }

    private static func encryptPayload(
        plaintextData: Data,
        recipientMessagingPubkeyHex: String
    ) throws -> ShareExtensionEncryptedBinaryPayload {
        let recipientPublicKeyData = try strictHexData(recipientMessagingPubkeyHex)
        let recipientPublicKey: Curve25519.KeyAgreement.PublicKey

        do {
            recipientPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipientPublicKeyData)
        } catch {
            throw CryptoError.invalidRecipientPublicKey
        }

        let ephemeralPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let sharedSecret = try ephemeralPrivateKey.sharedSecretFromKeyAgreement(with: recipientPublicKey)
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("split.messaging.v1".utf8),
            sharedInfo: Data(),
            outputByteCount: 32
        )

        do {
            let sealedBox = try ChaChaPoly.seal(plaintextData, using: symmetricKey)
            var ciphertextWithTag = Data()
            ciphertextWithTag.append(sealedBox.ciphertext)
            ciphertextWithTag.append(sealedBox.tag)
            let nonceData = Data(Array(sealedBox.nonce))

            return ShareExtensionEncryptedBinaryPayload(
                ciphertext: ciphertextWithTag,
                nonce: nonceData,
                senderEphemeralPubkey: hexString(for: ephemeralPrivateKey.publicKey.rawRepresentation)
            )
        } catch {
            throw CryptoError.invalidCiphertext
        }
    }

    private static func strictHexData(_ hex: String) throws -> Data {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count.isMultiple(of: 2) else {
            throw CryptoError.invalidRecipientPublicKey
        }

        var data = Data(capacity: cleaned.count / 2)
        var index = cleaned.startIndex

        while index < cleaned.endIndex {
            let nextIndex = cleaned.index(index, offsetBy: 2)
            let byteString = cleaned[index..<nextIndex]

            guard let byte = UInt8(String(byteString), radix: 16) else {
                throw CryptoError.invalidRecipientPublicKey
            }

            data.append(byte)
            index = nextIndex
        }

        return data
    }

    private static func hexString(for data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
final class ShareExtensionMessagingClient {
    static let shared = ShareExtensionMessagingClient()

    private enum IdentityEndpoint {
        case v3

        var path: String { "/messaging/v3/identity" }
        var signatureVersion: Int { 2 }
        var claimsActiveBinding: Bool { true }
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

    private struct NonceResponse: Codable {
        let nonce: String
        let expiresAt: String?
        let messageToSign: String
    }

    private struct WalletLoginRequest: Codable {
        let pubkey: String
        let nonce: String
        let signature: String
        let iat: Int
        let sparkAddress: String
    }

    private struct ErrorResponse: Codable {
        let error: String?
        let message: String?
    }

    private struct MessagingKeyState {
        let privateKey: Curve25519.KeyAgreement.PrivateKey
        let didCreate: Bool
    }

    private let messagingPrivateKeyKeychainKeyBase = "split.messaging.v2.privateKey"
    private let maximumAttachmentBytes = 50 * 1024 * 1024
    private let lightningAddressLookupRetryDelayNanoseconds: UInt64 = 500_000_000
    private let lightningAddressLookupMaxAttempts = 4
    private let assumedSessionLifetimeSeconds: TimeInterval = 60 * 60

    private var sdk: BreezSdk?
    private var connectTask: Task<Void, Error>?
    private var sessionValidUntil: Date?
    private var inFlightAuthTask: Task<Void, Error>?

    private init() {}

    func prewarm() async {
        do {
            try await ensureConnected()
            try await ensureSession()
        } catch {
            print("Share extension prewarm skipped: \(error.localizedDescription)")
        }
    }

    func send(
        payload: PendingSharedMessagePayload,
        recipientLightningAddress: String,
        messageText: String
    ) async throws {
        let normalizedRecipient = try normalizeLightningAddress(recipientLightningAddress)
        let senderBinding = try await ensureMessagingBinding()
        let recipient = try await resolveRecipient(lightningAddress: normalizedRecipient)

        switch payload.kind {
        case .text, .url:
            let trimmedText = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else {
                throw ShareExtensionMessageCrypto.CryptoError.invalidPlaintext
            }

            try await sendResolvedMessage(
                senderBinding: senderBinding,
                recipient: recipient,
                plaintext: trimmedText,
                messageType: "text",
                attachmentIds: nil
            )

        case .image, .video:
            let attachmentURL = ShareMessageExtensionStorage.fileURL(forRelativePath: payload.relativeFilePath)
            guard let attachmentURL else {
                throw ShareExtensionMessagingError.missingSharedFile
            }

            let fileData = try Data(contentsOf: attachmentURL)
            guard fileData.count <= maximumAttachmentBytes else {
                throw ShareExtensionMessagingError.attachmentTooLarge(maxBytes: maximumAttachmentBytes)
            }

            let mimeType = payload.mimeType ?? "application/octet-stream"
            let imageDimensions = imageDimensionsIfPossible(from: fileData, mimeType: mimeType)

            let encryptedAttachment = try ShareExtensionMessageCrypto.encryptAttachmentData(
                fileData,
                recipientMessagingPubkeyHex: recipient.messagingPubkey
            )

            let attachmentRecord = try await uploadEncryptedAttachment(
                fileData: encryptedAttachment.ciphertext,
                recipient: recipient,
                fileName: "\(UUID().uuidString.lowercased()).bin",
                mimeType: "application/octet-stream"
            )

            let attachmentPayload = ShareExtensionAttachmentMessagePayload(
                attachmentId: attachmentRecord.attachmentId,
                fileName: payload.fileName ?? defaultFileName(for: payload),
                mimeType: mimeType,
                sizeBytes: fileData.count,
                imageWidth: imageDimensions?.width,
                imageHeight: imageDimensions?.height,
                attachmentNonce: encryptedAttachment.nonce,
                attachmentSenderEphemeralPubkey: encryptedAttachment.senderEphemeralPubkey
            )

            let encodedAttachmentPayload = try ShareExtensionMessagePayloadCodec.encodeAttachment(attachmentPayload)

            try await sendResolvedMessage(
                senderBinding: senderBinding,
                recipient: recipient,
                plaintext: encodedAttachmentPayload,
                messageType: "attachment",
                attachmentIds: [attachmentRecord.attachmentId]
            )

            let trimmedText = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedText.isEmpty {
                try await sendResolvedMessage(
                    senderBinding: senderBinding,
                    recipient: recipient,
                    plaintext: trimmedText,
                    messageType: "text",
                    attachmentIds: nil
                )
            }
        }
    }

    private func ensureConnected() async throws {
        if sdk != nil {
            return
        }

        if let connectTask {
            try await connectTask.value
            return
        }

        let task = Task<Void, Error> {
            guard let seed = ShareExtensionKeychainHelper.read(forKey: ShareExtensionKeychainHelper.walletSeedKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !seed.isEmpty else {
                throw ShareExtensionMessagingError.missingWalletSeed
            }

            let apiKey = try await fetchBreezApiKey()
            var config = defaultConfig(network: .mainnet)
            config.apiKey = apiKey
            config.lnurlDomain = ShareExtensionAppConfig.lightningAddressDomain
            config.privateEnabledDefault = true

            let storageDir = try makeStorageDir()
            let connectedSdk = try await connect(
                request: ConnectRequest(
                    config: config,
                    seed: Seed.mnemonic(mnemonic: seed, passphrase: nil),
                    storageDir: storageDir
                )
            )

            self.sdk = connectedSdk
        }

        connectTask = task
        defer { connectTask = nil }
        try await task.value
    }

    private func ensureSession() async throws {
        try await ensureConnected()

        if let until = sessionValidUntil, until > Date() {
            return
        }

        if let inFlightAuthTask {
            try await inFlightAuthTask.value
            return
        }

        let task = Task<Void, Error> {
            if try await checkSessionCookieOnServer() {
                self.sessionValidUntil = Date().addingTimeInterval(self.assumedSessionLifetimeSeconds)
                return
            }

            try await loginWithWallet()
            self.sessionValidUntil = Date().addingTimeInterval(self.assumedSessionLifetimeSeconds)
        }

        inFlightAuthTask = task
        defer { inFlightAuthTask = nil }
        try await task.value
    }

    private func loginWithWallet() async throws {
        let nonceResponse = try await fetchNonce()
        let signed = try await signMessage(nonceResponse.messageToSign)
        let sparkAddress = try await fetchSparkAddress()

        try await exchangeSignatureForCookie(
            pubkey: signed.pubkey,
            nonce: nonceResponse.nonce,
            signature: signed.signature,
            iat: Int(Date().timeIntervalSince1970),
            sparkAddress: sparkAddress
        )
    }

    private func currentWalletPubkey() async throws -> String {
        try await ensureConnected()

        guard let sdk else {
            throw ShareExtensionMessagingError.invalidResponse
        }

        let info = try await sdk.getInfo(request: GetInfoRequest(ensureSynced: false))
        return info.identityPubkey
    }

    private func fetchLocalLightningAddressWithRetry() async throws -> String? {
        try await ensureConnected()

        var lastResult: String?

        for attempt in 1...lightningAddressLookupMaxAttempts {
            if let sdk {
                lastResult = try await sdk.getLightningAddress()?.lightningAddress
            }

            if let lastResult,
               !lastResult.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return lastResult
            }

            guard attempt < lightningAddressLookupMaxAttempts else {
                break
            }

            try? await Task.sleep(nanoseconds: lightningAddressLookupRetryDelayNanoseconds)
        }

        return lastResult
    }

    private func ensureMessagingBinding() async throws -> ShareExtensionMessagingIdentityBindingPayload {
        try await ensureSession()

        let walletPubkey = try await currentWalletPubkey()
        guard let lightningAddress = try await fetchLocalLightningAddressWithRetry()?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !lightningAddress.isEmpty else {
            throw ShareExtensionMessagingError.missingLightningAddress
        }

        var keyState = try loadOrCreatePrivateKey()
        var localIdentity = LocalIdentity(
            walletPubkey: walletPubkey,
            lightningAddress: lightningAddress,
            messagingPubkey: hexString(for: keyState.privateKey.publicKey.rawRepresentation)
        )

        let current = try await fetchCurrentRegistration()
        if isRegistrationValid(current, localIdentity: localIdentity),
           let binding = current.identityBindingPayload {
            return binding
        }

        if IdentityEndpoint.v3.claimsActiveBinding,
           let currentMessagingPubkey = current.messagingPubkey?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           !currentMessagingPubkey.isEmpty,
           currentMessagingPubkey != localIdentity.messagingPubkey {
            let rotatedPrivateKey = Curve25519.KeyAgreement.PrivateKey()
            savePrivateKey(rotatedPrivateKey)
            keyState = MessagingKeyState(privateKey: rotatedPrivateKey, didCreate: true)
            localIdentity = LocalIdentity(
                walletPubkey: localIdentity.walletPubkey,
                lightningAddress: localIdentity.lightningAddress,
                messagingPubkey: hexString(for: rotatedPrivateKey.publicKey.rawRepresentation)
            )
        }

        let signedAt = Int(Date().timeIntervalSince1970)
        let canonicalMessage = ShareExtensionMessageKeyBindingVerifier.buildMessagingIdentityBindingMessage(
            version: IdentityEndpoint.v3.signatureVersion,
            walletPubkey: localIdentity.walletPubkey,
            lightningAddress: localIdentity.lightningAddress,
            messagingPubkey: localIdentity.messagingPubkey,
            signedAt: signedAt
        )
        let signed = try await signMessage(canonicalMessage)

        guard signed.pubkey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == localIdentity.walletPubkey.lowercased() else {
            throw ShareExtensionMessagingError.invalidResponse
        }

        let response = try await postRegistration(
            requestBody: MessagingIdentityRegistrationRequest(
                walletPubkey: signed.pubkey,
                lightningAddress: localIdentity.lightningAddress,
                messagingPubkey: localIdentity.messagingPubkey,
                messagingIdentitySignature: signed.signature,
                messagingIdentitySignatureVersion: IdentityEndpoint.v3.signatureVersion,
                messagingIdentitySignedAt: signedAt
            )
        )

        guard isRegistrationValid(response, localIdentity: localIdentity),
              let binding = response.identityBindingPayload else {
            throw ShareExtensionMessagingError.invalidResponse
        }

        return binding
    }

    private func resolveRecipient(lightningAddress: String) async throws -> ShareExtensionMessagingRecipient {
        try await ensureSession()

        guard let url = URL(string: "\(ShareExtensionAppConfig.baseURL)/messaging/v3/directory/lookup") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(["lightningAddress": lightningAddress])

        let (data, response) = try await performAuthenticatedRequest(request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "ShareExtensionResolveRecipient",
                code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                userInfo: [NSLocalizedDescriptionKey: raw.isEmpty ? "Recipient lookup failed." : raw]
            )
        }

        let decoded = try decodeDateAware(ShareExtensionResolveRecipientResponse.self, from: data)
        try ShareExtensionMessageKeyBindingVerifier.verifyBinding(decoded.recipient.identityBindingPayload)
        try ShareExtensionMessagingDirectoryVerifier.verifyDirectoryProof(
            binding: decoded.recipient.identityBindingPayload,
            directory: decoded.directory
        )
        try ShareExtensionMessageDirectoryCheckpointStore.storeIfNewer(decoded.directory.checkpoint)
        try ShareExtensionMessageRecipientTrustStore.enforceOrPin(decoded.recipient.identityBindingPayload)
        return decoded.recipient
    }

    private func sendResolvedMessage(
        senderBinding: ShareExtensionMessagingIdentityBindingPayload,
        recipient: ShareExtensionMessagingRecipient,
        plaintext: String,
        messageType: String,
        attachmentIds: [String]?
    ) async throws {
        let createdAtClient = Date()
        let createdAtClientMs = Int64((createdAtClient.timeIntervalSince1970 * 1000).rounded())
        let clientMessageId = UUID().uuidString.lowercased()

        let encryptedPayload = try ShareExtensionMessageCrypto.encrypt(
            plaintext: try await buildSealedSenderPayloadString(
                plaintext: plaintext,
                messageType: messageType,
                senderBinding: senderBinding,
                recipient: recipient,
                createdAtClientMs: createdAtClientMs,
                envelopeVersion: 3,
                clientMessageId: clientMessageId
            ),
            recipientMessagingPubkeyHex: recipient.messagingPubkey
        )

        var currentRecipient = recipient
        let response: ShareExtensionSendMessageResponse

        do {
            response = try await sendMessage(
                envelope: ShareExtensionSendMessageEnvelope(
                    clientMessageId: clientMessageId,
                    recipient: currentRecipient.identityBindingPayload,
                    ciphertext: encryptedPayload.ciphertext,
                    nonce: encryptedPayload.nonce,
                    senderEphemeralPubkey: encryptedPayload.senderEphemeralPubkey,
                    createdAtClientMs: createdAtClientMs,
                    envelopeVersion: encryptedPayload.envelopeVersion,
                    messageType: messageType,
                    attachmentIds: attachmentIds
                )
            )
        } catch ShareExtensionMessagingError.recipientBindingStale {
            guard attachmentIds?.isEmpty != false else {
                throw ShareExtensionMessagingError.recipientBindingStale
            }

            currentRecipient = try await resolveRecipient(lightningAddress: recipient.lightningAddress)
            let retriedEncryptedPayload = try ShareExtensionMessageCrypto.encrypt(
                plaintext: try await buildSealedSenderPayloadString(
                    plaintext: plaintext,
                    messageType: messageType,
                    senderBinding: senderBinding,
                    recipient: currentRecipient,
                    createdAtClientMs: createdAtClientMs,
                    envelopeVersion: 3,
                    clientMessageId: clientMessageId
                ),
                recipientMessagingPubkeyHex: currentRecipient.messagingPubkey
            )

            response = try await sendMessage(
                envelope: ShareExtensionSendMessageEnvelope(
                    clientMessageId: clientMessageId,
                    recipient: currentRecipient.identityBindingPayload,
                    ciphertext: retriedEncryptedPayload.ciphertext,
                    nonce: retriedEncryptedPayload.nonce,
                    senderEphemeralPubkey: retriedEncryptedPayload.senderEphemeralPubkey,
                    createdAtClientMs: createdAtClientMs,
                    envelopeVersion: retriedEncryptedPayload.envelopeVersion,
                    messageType: messageType,
                    attachmentIds: attachmentIds
                )
            )
        }

        guard response.ok else {
            throw ShareExtensionMessagingError.invalidResponse
        }

        ShareExtensionOutgoingMessageRelayStore.enqueue(
            ShareExtensionOutgoingMessageRelayRecord(
                id: response.message?.messageId ?? clientMessageId,
                conversationId: currentRecipient.walletPubkey,
                clientMessageId: clientMessageId,
                body: plaintext,
                createdAt: response.message?.createdAtClient ?? response.message?.createdAt ?? createdAtClient,
                senderWalletPubkey: senderBinding.walletPubkey,
                senderMessagingPubkey: senderBinding.messagingPubkey,
                senderLightningAddress: senderBinding.lightningAddress,
                recipientWalletPubkey: currentRecipient.walletPubkey,
                recipientMessagingPubkey: currentRecipient.messagingPubkey,
                recipientLightningAddress: currentRecipient.lightningAddress,
                messageType: messageType
            )
        )
    }

    private func buildSealedSenderPayloadString(
        plaintext: String,
        messageType: String,
        senderBinding: ShareExtensionMessagingIdentityBindingPayload,
        recipient: ShareExtensionMessagingRecipient,
        createdAtClientMs: Int64,
        envelopeVersion: Int,
        clientMessageId: String
    ) async throws -> String {
        let signatureVersion = 2
        let canonicalEnvelopeMessage = ShareExtensionMessageKeyBindingVerifier.buildMessagingEnvelopeSignatureMessage(
            version: signatureVersion,
            clientMessageId: clientMessageId,
            senderBinding: senderBinding,
            recipientWalletPubkey: recipient.walletPubkey,
            recipientLightningAddress: recipient.lightningAddress,
            recipientMessagingPubkey: recipient.messagingPubkey,
            messageType: messageType,
            plaintext: plaintext,
            createdAtClientMs: createdAtClientMs,
            envelopeVersion: envelopeVersion
        )
        let signedEnvelope = try await signMessage(canonicalEnvelopeMessage)
        guard signedEnvelope.pubkey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == senderBinding.walletPubkey.lowercased() else {
            throw ShareExtensionMessagingError.invalidResponse
        }

        let sealedPayload = ShareExtensionSealedSenderMessagePayload(
            body: plaintext,
            sender: senderBinding,
            senderEnvelopeSignature: signedEnvelope.signature,
            senderEnvelopeSignatureVersion: signatureVersion
        )

        let sealedPayloadData = try JSONEncoder().encode(sealedPayload)
        guard let sealedPayloadString = String(data: sealedPayloadData, encoding: .utf8) else {
            throw ShareExtensionMessageCrypto.CryptoError.invalidPlaintext
        }

        return sealedPayloadString
    }

    private func sendMessage(envelope: ShareExtensionSendMessageEnvelope) async throws -> ShareExtensionSendMessageResponse {
        try await ensureSession()

        guard let url = URL(string: "\(ShareExtensionAppConfig.baseURL)/messaging/v3/send") else {
            throw URLError(.badURL)
        }

        struct RequestBody: Encodable {
            let clientMessageId: String
            let recipient: ShareExtensionMessagingIdentityBindingPayload
            let ciphertext: String
            let nonce: String
            let senderEphemeralPubkey: String
            let createdAtClientMs: Int64
            let envelopeVersion: Int
            let messageType: String
            let attachmentIds: [String]?
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(
            RequestBody(
                clientMessageId: envelope.clientMessageId,
                recipient: envelope.recipient,
                ciphertext: envelope.ciphertext,
                nonce: envelope.nonce,
                senderEphemeralPubkey: envelope.senderEphemeralPubkey,
                createdAtClientMs: envelope.createdAtClientMs,
                envelopeVersion: envelope.envelopeVersion,
                messageType: envelope.messageType,
                attachmentIds: envelope.attachmentIds
            )
        )

        let (data, response) = try await performAuthenticatedRequest(request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            let normalizedRaw = raw.lowercased()
            if (response as? HTTPURLResponse)?.statusCode == 409 &&
                normalizedRaw.contains("recipient messaging") &&
                normalizedRaw.contains("stale") &&
                normalizedRaw.contains("resolve again") {
                throw ShareExtensionMessagingError.recipientBindingStale
            }
            throw NSError(
                domain: "ShareExtensionSendMessage",
                code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                userInfo: [NSLocalizedDescriptionKey: raw.isEmpty ? "Message send failed." : raw]
            )
        }

        return try decodeDateAware(ShareExtensionSendMessageResponse.self, from: data)
    }

    private func uploadEncryptedAttachment(
        fileData: Data,
        recipient: ShareExtensionMessagingRecipient,
        fileName: String,
        mimeType: String
    ) async throws -> ShareExtensionMessagingAttachmentRecord {
        try await ensureSession()

        guard let url = URL(string: "\(ShareExtensionAppConfig.baseURL)/messaging/v2/attachments/upload") else {
            throw URLError(.badURL)
        }

        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = makeMultipartBody(
            fileData: fileData,
            fileName: fileName,
            mimeType: mimeType,
            recipient: recipient.identityBindingPayload,
            boundary: boundary
        )

        let (data, response) = try await performAuthenticatedRequest(
            request,
            rebuildOnRetry: {
                var retried = request
                retried.httpBody = self.makeMultipartBody(
                    fileData: fileData,
                    fileName: fileName,
                    mimeType: mimeType,
                    recipient: recipient.identityBindingPayload,
                    boundary: boundary
                )
                return retried
            }
        )

        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "ShareExtensionAttachmentUpload",
                code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                userInfo: [NSLocalizedDescriptionKey: raw.isEmpty ? "Attachment upload failed." : raw]
            )
        }

        return try decodeDateAware(ShareExtensionAttachmentUploadResponse.self, from: data).attachment
    }

    private func makeMultipartBody(
        fileData: Data,
        fileName: String,
        mimeType: String,
        recipient: ShareExtensionMessagingIdentityBindingPayload,
        boundary: String
    ) -> Data {
        var body = Data()

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"walletPubkey\"\r\n\r\n")
        body.append(recipient.walletPubkey)
        body.append("\r\n")

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"lightningAddress\"\r\n\r\n")
        body.append(recipient.lightningAddress)
        body.append("\r\n")

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"messagingPubkey\"\r\n\r\n")
        body.append(recipient.messagingPubkey)
        body.append("\r\n")

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"messagingIdentitySignature\"\r\n\r\n")
        body.append(recipient.messagingIdentitySignature)
        body.append("\r\n")

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"messagingIdentitySignatureVersion\"\r\n\r\n")
        body.append(String(recipient.messagingIdentitySignatureVersion))
        body.append("\r\n")

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"messagingIdentitySignedAt\"\r\n\r\n")
        body.append(String(recipient.messagingIdentitySignedAt))
        body.append("\r\n")

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"attachment\"; filename=\"\(fileName)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        body.append("\r\n")
        body.append("--\(boundary)--\r\n")

        return body
    }

    private func fetchCurrentRegistration() async throws -> ShareExtensionRegistrationResponse {
        try await ensureSession()

        guard let url = URL(string: "\(ShareExtensionAppConfig.baseURL)\(IdentityEndpoint.v3.path)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = true
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await performAuthenticatedRequest(request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw ShareExtensionMessagingError.invalidResponse
        }

        return try decodeDateAware(ShareExtensionRegistrationResponse.self, from: data)
    }

    private func postRegistration(
        requestBody: MessagingIdentityRegistrationRequest
    ) async throws -> ShareExtensionRegistrationResponse {
        try await ensureSession()

        guard let url = URL(string: "\(ShareExtensionAppConfig.baseURL)\(IdentityEndpoint.v3.path)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await performAuthenticatedRequest(request)
        guard let http = response as? HTTPURLResponse else {
            throw ShareExtensionMessagingError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            let serverMessage: String
            if let decoded = try? decodeDateAware(ShareExtensionRegistrationResponse.self, from: data),
               let error = decoded.error,
               !error.isEmpty {
                serverMessage = error
            } else {
                serverMessage = String(data: data, encoding: .utf8) ?? "Unknown server error"
            }

            throw NSError(
                domain: "ShareExtensionRegistration",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: serverMessage]
            )
        }

        return try decodeDateAware(ShareExtensionRegistrationResponse.self, from: data)
    }

    private func isRegistrationValid(
        _ response: ShareExtensionRegistrationResponse,
        localIdentity: LocalIdentity
    ) -> Bool {
        guard let binding = response.identityBindingPayload,
              binding.messagingIdentitySignatureVersion == IdentityEndpoint.v3.signatureVersion,
              binding.walletPubkey.lowercased() == localIdentity.walletPubkey.lowercased(),
              binding.lightningAddress == localIdentity.lightningAddress,
              binding.messagingPubkey == localIdentity.messagingPubkey else {
            return false
        }

        do {
            try ShareExtensionMessageKeyBindingVerifier.verifyBinding(binding)
            guard let directory = response.directory else {
                return false
            }

            try ShareExtensionMessagingDirectoryVerifier.verifyDirectoryProof(
                binding: binding,
                directory: directory
            )
            try ShareExtensionMessageDirectoryCheckpointStore.storeIfNewer(directory.checkpoint)
            return true
        } catch {
            return false
        }
    }

    private func loadOrCreatePrivateKey() throws -> MessagingKeyState {
        if let privateKey = try loadPrivateKeyIfPresent() {
            return MessagingKeyState(privateKey: privateKey, didCreate: false)
        }

        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        savePrivateKey(privateKey)
        return MessagingKeyState(privateKey: privateKey, didCreate: true)
    }

    private func loadPrivateKeyIfPresent() throws -> Curve25519.KeyAgreement.PrivateKey? {
        let preferredKey = preferredMessagingPrivateKeyKeychainKey()

        for key in readableMessagingPrivateKeyKeychainKeys() {
            guard let stored = ShareExtensionKeychainHelper.read(forKey: key) else {
                continue
            }

            let privateKey: Curve25519.KeyAgreement.PrivateKey
            do {
                privateKey = try decodePrivateKey(from: stored)
            } catch {
                ShareExtensionKeychainHelper.delete(forKey: key)
                continue
            }

            if key != preferredKey,
               ShareExtensionKeychainHelper.read(forKey: preferredKey) == nil {
                ShareExtensionKeychainHelper.save(stored, forKey: preferredKey)
            }

            return privateKey
        }

        return nil
    }

    private func performAuthenticatedRequest(
        _ request: URLRequest,
        rebuildOnRetry: (() -> URLRequest)? = nil
    ) async throws -> (Data, URLResponse) {
        var request = request
        var (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse,
           http.statusCode == 401 || http.statusCode == 403 {
            invalidateSession()
            try await ensureSession()
            request = rebuildOnRetry?() ?? request
            (data, response) = try await URLSession.shared.data(for: request)
        }

        return (data, response)
    }

    private func checkSessionCookieOnServer() async throws -> Bool {
        guard let url = URL(string: "\(ShareExtensionAppConfig.baseURL)/session") else {
            throw ShareExtensionMessagingError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = true

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ShareExtensionMessagingError.invalidResponse
        }

        return http.statusCode == 200
    }

    private func fetchNonce() async throws -> NonceResponse {
        guard let url = URL(string: "\(ShareExtensionAppConfig.baseURL)/auth/nonce") else {
            throw ShareExtensionMessagingError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ShareExtensionMessagingError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            throw decodeServerError(data: data, status: http.statusCode, fallback: "Nonce request failed")
        }

        guard let decoded = try? JSONDecoder().decode(NonceResponse.self, from: data) else {
            throw ShareExtensionMessagingError.invalidResponse
        }

        return decoded
    }

    private func exchangeSignatureForCookie(
        pubkey: String,
        nonce: String,
        signature: String,
        iat: Int,
        sparkAddress: String
    ) async throws {
        guard let url = URL(string: "\(ShareExtensionAppConfig.baseURL)/auth/wallet-login") else {
            throw ShareExtensionMessagingError.invalidResponse
        }

        let body = WalletLoginRequest(
            pubkey: pubkey,
            nonce: nonce,
            signature: signature,
            iat: iat,
            sparkAddress: sparkAddress
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ShareExtensionMessagingError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            throw decodeServerError(data: data, status: http.statusCode, fallback: "Wallet login failed")
        }
    }

    private func decodeServerError(data: Data, status: Int, fallback: String) -> Error {
        if let decoded = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
            let message = decoded.error ?? decoded.message ?? fallback
            return NSError(
                domain: "ShareExtensionAuth",
                code: status,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }

        let raw = String(data: data, encoding: .utf8)
        return NSError(
            domain: "ShareExtensionAuth",
            code: status,
            userInfo: [NSLocalizedDescriptionKey: raw?.isEmpty == false ? raw! : fallback]
        )
    }

    private func fetchSparkAddress() async throws -> String {
        try await ensureConnected()
        guard let sdk else {
            throw ShareExtensionMessagingError.invalidResponse
        }

        let response = try await sdk.receivePayment(
            request: ReceivePaymentRequest(paymentMethod: ReceivePaymentMethod.sparkAddress)
        )
        return response.paymentRequest
    }

    private func signMessage(_ message: String) async throws -> SignMessageResponse {
        try await ensureConnected()
        guard let sdk else {
            throw ShareExtensionMessagingError.invalidResponse
        }

        return try await sdk.signMessage(
            request: SignMessageRequest(message: message, compact: true)
        )
    }

    private func fetchBreezApiKey() async throws -> String {
        guard let url = URL(string: "\(ShareExtensionAppConfig.baseURL)/breez-api-key") else {
            throw ShareExtensionMessagingError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ShareExtensionMessagingError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Failed to fetch Breez API key."
            throw NSError(
                domain: "ShareExtensionBreezAPIKey",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }

        struct Response: Decodable {
            let apiKey: String
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard !decoded.apiKey.isEmpty else {
            throw ShareExtensionMessagingError.invalidResponse
        }

        return decoded.apiKey
    }

    private func makeStorageDir() throws -> String {
        let baseDirectory = try ShareMessageExtensionStorage.sharedContainerURL()
            .appendingPathComponent("ShareExtensionWallet", isDirectory: true)
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        return baseDirectory.path
    }

    private func invalidateSession() {
        sessionValidUntil = nil
    }

    private func decodePrivateKey(
        from stored: String
    ) throws -> Curve25519.KeyAgreement.PrivateKey {
        guard let data = Data(base64Encoded: stored) else {
            throw ShareExtensionMessagingError.invalidStoredKey
        }

        do {
            return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
        } catch {
            throw ShareExtensionMessagingError.invalidStoredKey
        }
    }

    private func preferredMessagingPrivateKeyKeychainKey() -> String {
        "\(messagingPrivateKeyKeychainKeyBase).\(ShareExtensionAppConfig.messagingPushEnvironment)"
    }

    private func readableMessagingPrivateKeyKeychainKeys() -> [String] {
        [
            preferredMessagingPrivateKeyKeychainKey(),
            messagingPrivateKeyKeychainKeyBase
        ]
    }

    private func savePrivateKey(_ privateKey: Curve25519.KeyAgreement.PrivateKey) {
        let encoded = privateKey.rawRepresentation.base64EncodedString()
        ShareExtensionKeychainHelper.save(encoded, forKey: preferredMessagingPrivateKeyKeychainKey())
    }

    private func imageDimensionsIfPossible(from fileData: Data, mimeType: String) -> (width: Int, height: Int)? {
        guard mimeType.lowercased().hasPrefix("image/"),
              let image = UIImage(data: fileData) else {
            return nil
        }

        let width = image.cgImage?.width ?? Int(image.size.width)
        let height = image.cgImage?.height ?? Int(image.size.height)
        return (width, height)
    }

    private func defaultFileName(for payload: PendingSharedMessagePayload) -> String {
        switch payload.kind {
        case .image:
            return "shared-photo"
        case .video:
            return "shared-video"
        case .text:
            return "shared-text"
        case .url:
            return "shared-link"
        }
    }

    private func normalizeLightningAddress(_ rawValue: String) throws -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            throw ShareExtensionMessagingError.invalidRecipient
        }

        let normalized: String
        if trimmed.contains("@") {
            normalized = trimmed
        } else {
            normalized = "\(trimmed)@\(ShareExtensionAppConfig.lightningAddressDomain)"
        }

        let pieces = normalized.split(separator: "@", omittingEmptySubsequences: false)
        guard pieces.count == 2,
              !pieces[0].isEmpty,
              !pieces[1].isEmpty else {
            throw ShareExtensionMessagingError.invalidRecipient
        }

        return normalized
    }

    private func decodeDateAware<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
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

        return try decoder.decode(type, from: data)
    }

    private func hexString(for data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

private extension Data {
    init(hex: String) {
        self.init()
        reserveCapacity(hex.count / 2)

        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            let byteString = hex[index..<next]
            append(UInt8(byteString, radix: 16) ?? 0)
            index = next
        }
    }

    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
