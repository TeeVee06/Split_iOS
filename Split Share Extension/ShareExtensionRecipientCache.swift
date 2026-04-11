//
//  ShareExtensionRecipientCache.swift
//  Split Share Extension
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
    static let appGroupIdentifier = ShareExtensionAppConfig.sharedAppGroupIdentifier
    private static let defaultsKey = "sharedMessageRecipientRecords"

    static func load() -> [SharedMessageRecipientRecord] {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let encoded = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([SharedMessageRecipientRecord].self, from: encoded) else {
            return []
        }

        return decoded
    }
}
