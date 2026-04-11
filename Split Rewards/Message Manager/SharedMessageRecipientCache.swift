//
//  SharedMessageRecipientCache.swift
//  Split Rewards
//
//

import Foundation

struct SharedMessageRecipientRecord: Codable, Equatable, Identifiable, Hashable {
    enum Source: String, Codable {
        case contact
        case conversation
    }

    let lightningAddress: String
    let displayName: String
    let profilePicURL: String?
    let lastInteractedAt: Date?
    let source: Source

    var id: String { lightningAddress }
}

enum SharedMessageRecipientCache {
    static let appGroupIdentifier = AppConfig.sharedAppGroupIdentifier
    private static let defaultsKey = "sharedMessageRecipientRecords"

    static func load() -> [SharedMessageRecipientRecord] {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let encoded = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([SharedMessageRecipientRecord].self, from: encoded) else {
            return []
        }

        return decoded
    }

    static func store(
        contacts: [SharedMessageRecipientRecord],
        conversations: [SharedMessageRecipientRecord]
    ) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return
        }

        var mergedByAddress: [String: SharedMessageRecipientRecord] = [:]

        for record in conversations + contacts {
            let normalizedAddress = normalize(record.lightningAddress)
            guard !normalizedAddress.isEmpty else { continue }

            let normalizedDisplayName = record.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let candidate = SharedMessageRecipientRecord(
                lightningAddress: normalizedAddress,
                displayName: normalizedDisplayName.isEmpty ? normalizedAddress : normalizedDisplayName,
                profilePicURL: normalizedProfileURL(record.profilePicURL),
                lastInteractedAt: record.lastInteractedAt,
                source: record.source
            )

            if let existing = mergedByAddress[normalizedAddress] {
                mergedByAddress[normalizedAddress] = merge(existing: existing, incoming: candidate)
            } else {
                mergedByAddress[normalizedAddress] = candidate
            }
        }

        let records = mergedByAddress.values.sorted { lhs, rhs in
            let lhsDate = lhs.lastInteractedAt ?? .distantPast
            let rhsDate = rhs.lastInteractedAt ?? .distantPast
            if lhsDate == rhsDate {
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            return lhsDate > rhsDate
        }

        if let encoded = try? JSONEncoder().encode(records) {
            defaults.set(encoded, forKey: defaultsKey)
        }
    }

    private static func merge(
        existing: SharedMessageRecipientRecord,
        incoming: SharedMessageRecipientRecord
    ) -> SharedMessageRecipientRecord {
        let preferredDisplayName: String
        switch (existing.source, incoming.source) {
        case (.contact, _):
            preferredDisplayName = existing.displayName
        case (_, .contact):
            preferredDisplayName = incoming.displayName
        default:
            preferredDisplayName = existing.displayName.count >= incoming.displayName.count
                ? existing.displayName
                : incoming.displayName
        }

        let preferredProfilePicURL = normalizedProfileURL(incoming.profilePicURL) ?? normalizedProfileURL(existing.profilePicURL)

        let preferredDate: Date?
        switch (existing.lastInteractedAt, incoming.lastInteractedAt) {
        case let (lhs?, rhs?):
            preferredDate = max(lhs, rhs)
        case let (lhs?, nil):
            preferredDate = lhs
        case let (nil, rhs?):
            preferredDate = rhs
        default:
            preferredDate = nil
        }

        let preferredSource: SharedMessageRecipientRecord.Source =
            existing.source == .contact || incoming.source == .contact ? .contact : .conversation

        return SharedMessageRecipientRecord(
            lightningAddress: existing.lightningAddress,
            displayName: preferredDisplayName,
            profilePicURL: preferredProfilePicURL,
            lastInteractedAt: preferredDate,
            source: preferredSource
        )
    }

    private static func normalize(_ lightningAddress: String) -> String {
        lightningAddress
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func normalizedProfileURL(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
