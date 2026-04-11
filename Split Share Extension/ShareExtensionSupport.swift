//
//  ShareExtensionSupport.swift
//  Split Share Extension
//
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UIKit

enum SharedMessageShareKind: String, Codable {
    case text
    case url
    case image
    case video
}

struct PendingSharedMessagePayload: Codable, Equatable, Identifiable {
    let id: String
    let createdAt: Date
    let kind: SharedMessageShareKind
    let text: String?
    let fileName: String?
    let mimeType: String?
    let relativeFilePath: String?

    var previewTitle: String {
        switch kind {
        case .text:
            return "Shared text"
        case .url:
            return "Shared link"
        case .image:
            return "Shared photo"
        case .video:
            return "Shared video"
        }
    }

    var previewSubtitle: String {
        switch kind {
        case .text, .url:
            let trimmedText = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmedText.isEmpty {
                return "Send this item in an encrypted Split message."
            }

            return String(trimmedText.prefix(160))
        case .image, .video:
            return fileName ?? "Send this item in an encrypted Split message."
        }
    }
}

enum ShareMessageExtensionStorage {
    static let appGroupIdentifier = ShareExtensionAppConfig.sharedAppGroupIdentifier

    static func sharedContainerURL() throws -> URL {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw ShareMessageExtensionError.storageUnavailable
        }

        return containerURL
    }

    static func fileURL(forRelativePath relativePath: String?) -> URL? {
        guard let relativePath,
              !relativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let containerURL = try? sharedContainerURL() else {
            return nil
        }

        return containerURL.appendingPathComponent(relativePath)
    }

    static func cleanupWorkingPayload(_ payload: PendingSharedMessagePayload) {
        guard let fileURL = fileURL(forRelativePath: payload.relativeFilePath),
              FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        try? FileManager.default.removeItem(at: fileURL)
    }
}

enum ShareMessageExtensionError: LocalizedError {
    case unsupportedContent
    case storageUnavailable
    case failedToLoadContent

    var errorDescription: String? {
        switch self {
        case .unsupportedContent:
            return "Split can currently share text, links, photos, and videos into messages."
        case .storageUnavailable:
            return "Split share storage is unavailable right now."
        case .failedToLoadContent:
            return "Couldn’t read the item you tried to share."
        }
    }
}

@MainActor
final class ShareMessageExtensionViewModel: ObservableObject {
    @Published private(set) var payload: PendingSharedMessagePayload?
    @Published private(set) var recipientSuggestions: [SharedMessageRecipientRecord] = []
    @Published private(set) var selectedRecipient: SharedMessageRecipientRecord?
    @Published var recipientQuery = ""
    @Published var composerText = ""
    @Published var errorMessage: String?
    @Published private(set) var isLoading = true
    @Published private(set) var isSending = false

    private var extensionContext: NSExtensionContext?
    private var allRecipientRecords: [SharedMessageRecipientRecord] = []
    private let messagingClient = ShareExtensionMessagingClient.shared

    var canSendDirectly: Bool {
        guard !isLoading, !isSending, payload != nil else { return false }
        guard resolvedRecipientAddress != nil else { return false }

        if requiresMessageBody {
            return !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return true
    }

    var messagePlaceholder: String {
        switch payload?.kind {
        case .text:
            return "Edit the text you want to send"
        case .url:
            return "Add a note or send the link as-is"
        case .image, .video:
            return "Optional"
        case .none:
            return "Message"
        }
    }

    var showsRecipientSuggestions: Bool {
        selectedRecipient == nil
            && !trimmedRecipientQuery.isEmpty
            && (!recipientSuggestions.isEmpty || typedRecipientCandidate != nil)
    }

    var typedRecipientCandidate: String? {
        guard selectedRecipient == nil,
              shouldOfferTypedRecipientCandidate,
              let normalized = Self.normalizeRecipientInput(recipientQuery) else {
            return nil
        }

        let alreadyKnown = allRecipientRecords.contains { record in
            record.lightningAddress == normalized
        }

        return alreadyKnown ? nil : normalized
    }

    func configure(extensionContext: NSExtensionContext?) {
        self.extensionContext = extensionContext
    }

    func loadPayload() {
        guard let extensionItems = extensionContext?.inputItems else {
            isLoading = false
            errorMessage = ShareMessageExtensionError.failedToLoadContent.localizedDescription
            return
        }

        Task {
            do {
                let loadedPayload = try await ShareMessageExtensionLoader.loadFirstPayload(from: extensionItems)
                payload = loadedPayload
                composerText = initialComposerText(for: loadedPayload)
                errorMessage = nil
                allRecipientRecords = SharedMessageRecipientCache.load()
                refreshRecipientSuggestions()
                isLoading = false

                Task {
                    await messagingClient.prewarm()
                }
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    func setRecipientQuery(_ value: String) {
        guard selectedRecipient == nil else { return }

        recipientQuery = value
        refreshRecipientSuggestions()
    }

    func selectRecipient(_ recipient: SharedMessageRecipientRecord) {
        selectedRecipient = recipient
        recipientQuery = ""
        refreshRecipientSuggestions()
    }

    func selectTypedRecipientCandidate() {
        guard let candidate = typedRecipientCandidate else { return }

        selectRecipient(
            SharedMessageRecipientRecord(
                lightningAddress: candidate,
                displayName: candidate,
                profilePicURL: nil,
                lastInteractedAt: nil,
                source: .contact
            )
        )
    }

    func clearSelectedRecipient() {
        selectedRecipient = nil
        refreshRecipientSuggestions()
    }

    func cancel() {
        cleanupWorkingPayloadIfNeeded()
        extensionContext?.completeRequest(returningItems: nil)
    }

    func sendDirectly() {
        guard let payload else { return }
        guard let recipientAddress = resolvedRecipientAddress else {
            errorMessage = "Enter a valid Lightning Address."
            return
        }

        if requiresMessageBody,
           composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "Add the message text you want to send."
            return
        }

        isSending = true
        errorMessage = nil

        Task {
            do {
                try await messagingClient.send(
                    payload: payload,
                    recipientLightningAddress: recipientAddress,
                    messageText: composerText
                )

                ShareMessageExtensionStorage.cleanupWorkingPayload(payload)
                isSending = false
                extensionContext?.completeRequest(returningItems: nil)
            } catch {
                errorMessage = error.localizedDescription
                isSending = false
            }
        }
    }

    private var requiresMessageBody: Bool {
        switch payload?.kind {
        case .text, .url:
            return true
        case .image, .video, .none:
            return false
        }
    }

    private var resolvedRecipientAddress: String? {
        if let selectedRecipient {
            return selectedRecipient.lightningAddress
        }

        return Self.normalizeRecipientInput(recipientQuery)
    }

    private var trimmedRecipientQuery: String {
        Self.normalizedSearchText(recipientQuery)
    }

    private var shouldOfferTypedRecipientCandidate: Bool {
        let trimmedQuery = trimmedRecipientQuery
        guard !trimmedQuery.isEmpty else { return false }
        return trimmedQuery.contains("@") || recipientSuggestions.isEmpty
    }

    private func initialComposerText(for payload: PendingSharedMessagePayload) -> String {
        switch payload.kind {
        case .text, .url:
            return payload.text ?? ""
        case .image, .video:
            return ""
        }
    }

    private func cleanupWorkingPayloadIfNeeded() {
        guard let payload else { return }
        ShareMessageExtensionStorage.cleanupWorkingPayload(payload)
    }

    private func refreshRecipientSuggestions() {
        guard selectedRecipient == nil else {
            recipientSuggestions = []
            return
        }

        let trimmedQuery = trimmedRecipientQuery
        guard !trimmedQuery.isEmpty else {
            recipientSuggestions = []
            return
        }

        let matches = allRecipientRecords
            .compactMap { record -> (record: SharedMessageRecipientRecord, score: Int)? in
                guard let score = recipientMatchScore(for: record, query: trimmedQuery) else {
                    return nil
                }

                return (record, score)
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }

                let lhsDate = lhs.record.lastInteractedAt ?? .distantPast
                let rhsDate = rhs.record.lastInteractedAt ?? .distantPast
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }

                return lhs.record.displayName.localizedCaseInsensitiveCompare(rhs.record.displayName) == .orderedAscending
            }
            .prefix(8)
            .map(\.record)

        recipientSuggestions = Array(matches)
    }

    private func recipientMatchScore(
        for record: SharedMessageRecipientRecord,
        query: String
    ) -> Int? {
        let displayName = Self.normalizedSearchText(record.displayName)
        let displayNameKey = Self.compactSearchKey(record.displayName)
        let lightningAddress = Self.normalizedSearchText(record.lightningAddress)
        let username = lightningAddress.split(separator: "@").first.map(String.init) ?? ""
        let displayNameTokens = displayName.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let queryKey = Self.compactSearchKey(query)

        var bestScore = 0

        if displayName == query {
            bestScore = max(bestScore, 140)
        } else if !queryKey.isEmpty, displayNameKey == queryKey {
            bestScore = max(bestScore, 138)
        } else if displayName.hasPrefix(query) {
            bestScore = max(bestScore, 125)
        } else if !queryKey.isEmpty, displayNameKey.hasPrefix(queryKey) {
            bestScore = max(bestScore, 123)
        } else if displayNameTokens.contains(where: { $0.hasPrefix(query) }) {
            bestScore = max(bestScore, 115)
        } else if !queryKey.isEmpty,
                  displayNameTokens.contains(where: { Self.compactSearchKey(String($0)).hasPrefix(queryKey) }) {
            bestScore = max(bestScore, 113)
        } else if displayName.contains(query) {
            bestScore = max(bestScore, 100)
        } else if !queryKey.isEmpty, displayNameKey.contains(queryKey) {
            bestScore = max(bestScore, 98)
        }

        if lightningAddress == query {
            bestScore = max(bestScore, 96)
        } else if username == query {
            bestScore = max(bestScore, 94)
        } else if lightningAddress.hasPrefix(query) {
            bestScore = max(bestScore, 90)
        } else if username.hasPrefix(query) {
            bestScore = max(bestScore, 88)
        } else if lightningAddress.contains(query) || username.contains(query) {
            bestScore = max(bestScore, 80)
        }

        return bestScore > 0 ? bestScore : nil
    }

    private static func normalizedSearchText(_ rawValue: String) -> String {
        rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
    }

    private static func compactSearchKey(_ rawValue: String) -> String {
        normalizedSearchText(rawValue)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    private static func normalizeRecipientInput(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        let normalized: String
        if trimmed.contains("@") {
            normalized = trimmed
        } else {
            let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._-")
            guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
                return nil
            }
            normalized = "\(trimmed)@\(ShareExtensionAppConfig.lightningAddressDomain)"
        }

        let pieces = normalized.split(separator: "@", omittingEmptySubsequences: false)
        guard pieces.count == 2,
              !pieces[0].isEmpty,
              !pieces[1].isEmpty else {
            return nil
        }

        return normalized
    }
}

enum ShareMessageExtensionLoader {
    static func loadFirstPayload(from inputItems: [Any]) async throws -> PendingSharedMessagePayload {
        let extensionItems = inputItems.compactMap { $0 as? NSExtensionItem }

        for item in extensionItems {
            for provider in item.attachments ?? [] {
                if let urlPayload = try await loadURLPayloadIfPossible(from: provider) {
                    return urlPayload
                }

                if let textPayload = try await loadTextPayloadIfPossible(from: provider) {
                    return textPayload
                }

                if let imagePayload = try await loadFilePayloadIfPossible(
                    from: provider,
                    kind: .image,
                    contentType: .image
                ) {
                    return imagePayload
                }

                if let videoPayload = try await loadFilePayloadIfPossible(
                    from: provider,
                    kind: .video,
                    contentType: .movie
                ) {
                    return videoPayload
                }
            }
        }

        throw ShareMessageExtensionError.unsupportedContent
    }

    private static func loadURLPayloadIfPossible(from provider: NSItemProvider) async throws -> PendingSharedMessagePayload? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) else {
            return nil
        }

        let item = try await loadItem(from: provider, typeIdentifier: UTType.url.identifier)

        let urlValue: URL?
        if let url = item as? URL {
            urlValue = url
        } else if let nsURL = item as? NSURL {
            urlValue = nsURL as URL
        } else if let string = item as? String {
            urlValue = URL(string: string)
        } else {
            urlValue = nil
        }

        guard let urlValue else {
            throw ShareMessageExtensionError.failedToLoadContent
        }

        return PendingSharedMessagePayload(
            id: UUID().uuidString,
            createdAt: Date(),
            kind: .url,
            text: urlValue.absoluteString,
            fileName: nil,
            mimeType: nil,
            relativeFilePath: nil
        )
    }

    private static func loadTextPayloadIfPossible(from provider: NSItemProvider) async throws -> PendingSharedMessagePayload? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) else {
            return nil
        }

        let item = try await loadItem(from: provider, typeIdentifier: UTType.plainText.identifier)
        let textValue: String?

        if let string = item as? String {
            textValue = string
        } else if let attributedString = item as? NSAttributedString {
            textValue = attributedString.string
        } else if let nsString = item as? NSString {
            textValue = nsString as String
        } else {
            textValue = nil
        }

        guard let textValue,
              !textValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ShareMessageExtensionError.failedToLoadContent
        }

        return PendingSharedMessagePayload(
            id: UUID().uuidString,
            createdAt: Date(),
            kind: .text,
            text: textValue,
            fileName: nil,
            mimeType: nil,
            relativeFilePath: nil
        )
    }

    private static func loadFilePayloadIfPossible(
        from provider: NSItemProvider,
        kind: SharedMessageShareKind,
        contentType: UTType
    ) async throws -> PendingSharedMessagePayload? {
        guard provider.hasItemConformingToTypeIdentifier(contentType.identifier) else {
            return nil
        }

        let payloadID = UUID().uuidString
        let registeredTypeIdentifier = provider.registeredTypeIdentifiers.first(where: { identifier in
            guard let registeredType = UTType(identifier) else { return false }
            return registeredType.conforms(to: contentType)
        }) ?? contentType.identifier

        return try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: registeredTypeIdentifier) { temporaryURL, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let temporaryURL else {
                    continuation.resume(throwing: ShareMessageExtensionError.failedToLoadContent)
                    return
                }

                do {
                    let payload = try copySharedFile(
                        from: temporaryURL,
                        payloadID: payloadID,
                        suggestedName: provider.suggestedName,
                        typeIdentifier: registeredTypeIdentifier,
                        kind: kind
                    )
                    continuation.resume(returning: payload)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func loadItem(from provider: NSItemProvider, typeIdentifier: String) async throws -> NSSecureCoding {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let item else {
                    continuation.resume(throwing: ShareMessageExtensionError.failedToLoadContent)
                    return
                }

                continuation.resume(returning: item)
            }
        }
    }

    private static func copySharedFile(
        from temporaryURL: URL,
        payloadID: String,
        suggestedName: String?,
        typeIdentifier: String,
        kind: SharedMessageShareKind
    ) throws -> PendingSharedMessagePayload {
        let fileManager = FileManager.default
        let containerURL = try ShareMessageExtensionStorage.sharedContainerURL()
        let draftsDirectory = containerURL.appendingPathComponent("SharedMessageDrafts", isDirectory: true)
        try fileManager.createDirectory(at: draftsDirectory, withIntermediateDirectories: true)

        let resolvedType = UTType(typeIdentifier)
        let fileExtension = temporaryURL.pathExtension.isEmpty
            ? (resolvedType?.preferredFilenameExtension ?? "")
            : temporaryURL.pathExtension

        let defaultBaseName = kind == .image ? "shared-photo" : "shared-video"
        var fileName = suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? defaultBaseName
        if fileName.isEmpty {
            fileName = defaultBaseName
        }
        fileName = fileName.replacingOccurrences(of: "/", with: "-")

        if !fileExtension.isEmpty,
           !fileName.lowercased().hasSuffix(".\(fileExtension.lowercased())") {
            fileName += ".\(fileExtension)"
        }

        let relativePath = "SharedMessageDrafts/\(payloadID)-\(fileName)"
        let destinationURL = containerURL.appendingPathComponent(relativePath)

        if fileManager.fileExists(atPath: destinationURL.path) {
            try? fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: temporaryURL, to: destinationURL)

        return PendingSharedMessagePayload(
            id: payloadID,
            createdAt: Date(),
            kind: kind,
            text: nil,
            fileName: fileName,
            mimeType: resolvedType?.preferredMIMEType ?? mimeTypeForFile(at: destinationURL),
            relativeFilePath: relativePath
        )
    }

    private static func mimeTypeForFile(at url: URL) -> String {
        if let values = try? url.resourceValues(forKeys: [.contentTypeKey]),
           let contentType = values.contentType,
           let mimeType = contentType.preferredMIMEType {
            return mimeType
        }

        return "application/octet-stream"
    }
}
