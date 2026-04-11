import Foundation

struct MessagingBlockedUser: Identifiable, Decodable, Hashable {
    let blockId: String
    let blockedUserId: String
    let blockedWalletPubkey: String
    let blockedLightningAddress: String?
    let blockedProfilePicUrl: String?
    let createdAt: Date?
    let updatedAt: Date?

    var id: String { blockId }

    var normalizedLightningAddress: String? {
        let normalized = blockedLightningAddress?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let normalized, !normalized.isEmpty else { return nil }
        return normalized
    }
}

private struct MessagingBlockListResponse: Decodable {
    let ok: Bool
    let blocks: [MessagingBlockedUser]
}

private struct MessagingBlockMutationResponse: Decodable {
    let ok: Bool
    let didUpdate: Bool?
    let didDelete: Bool?
    let block: MessagingBlockedUser?
    let blockedWalletPubkey: String?
    let error: String?
}

enum MessagingBlockAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid messaging blocks endpoint URL."
        case .invalidResponse:
            return "Invalid messaging blocks response."
        case .serverError(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        }
    }
}

enum MessagingBlockAPI {
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let standardFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    @MainActor
    static func fetchBlocks(
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> [MessagingBlockedUser] {
        guard let url = URL(string: "\(AppConfig.baseURL)/messaging/blocks") else {
            throw MessagingBlockAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = true
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data = try await perform(request, authManager: authManager, walletManager: walletManager)

        do {
            return try decoder().decode(MessagingBlockListResponse.self, from: data).blocks
        } catch {
            throw MessagingBlockAPIError.invalidResponse
        }
    }

    @MainActor
    static func blockUser(
        walletPubkey: String?,
        lightningAddress: String?,
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> MessagingBlockedUser {
        guard let url = URL(string: "\(AppConfig.baseURL)/messaging/blocks") else {
            throw MessagingBlockAPIError.invalidURL
        }

        struct RequestBody: Encodable {
            let walletPubkey: String?
            let lightningAddress: String?
        }

        let normalizedWalletPubkey = walletPubkey?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank
        let normalizedLightningAddress = lightningAddress?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .nilIfBlank

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(
            RequestBody(
                walletPubkey: normalizedWalletPubkey,
                lightningAddress: normalizedLightningAddress
            )
        )

        let data = try await perform(request, authManager: authManager, walletManager: walletManager)

        do {
            let decoded = try decoder().decode(MessagingBlockMutationResponse.self, from: data)
            guard let block = decoded.block else {
                throw MessagingBlockAPIError.invalidResponse
            }
            NotificationCenter.default.post(name: .messagingBlocksDidChange, object: nil)
            return block
        } catch let error as MessagingBlockAPIError {
            throw error
        } catch {
            throw MessagingBlockAPIError.invalidResponse
        }
    }

    @MainActor
    static func unblockUser(
        blockedWalletPubkey: String,
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> Bool {
        let normalizedWalletPubkey = blockedWalletPubkey
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "\(AppConfig.baseURL)/messaging/blocks/\(normalizedWalletPubkey)") else {
            throw MessagingBlockAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.httpShouldHandleCookies = true
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data = try await perform(request, authManager: authManager, walletManager: walletManager)

        do {
            let decoded = try decoder().decode(MessagingBlockMutationResponse.self, from: data)
            NotificationCenter.default.post(name: .messagingBlocksDidChange, object: nil)
            return decoded.didDelete ?? false
        } catch {
            throw MessagingBlockAPIError.invalidResponse
        }
    }

    @MainActor
    private static func perform(
        _ request: URLRequest,
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> Data {
        try await authManager.ensureSession(walletManager: walletManager)

        var (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse,
           http.statusCode == 401 || http.statusCode == 403 {
            authManager.invalidateSession()
            try await authManager.ensureSession(walletManager: walletManager)
            (data, response) = try await URLSession.shared.data(for: request)
        }

        guard let http = response as? HTTPURLResponse else {
            throw MessagingBlockAPIError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            let serverMessage: String

            if let decoded = try? decoder().decode(MessagingBlockMutationResponse.self, from: data),
               let error = decoded.error,
               !error.isEmpty {
                serverMessage = error
            } else {
                serverMessage = String(data: data, encoding: .utf8) ?? "Unknown server error"
            }

            throw MessagingBlockAPIError.serverError(
                statusCode: http.statusCode,
                message: serverMessage
            )
        }

        return data
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            if let date = fractionalFormatter.date(from: value) {
                return date
            }

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
}

extension Notification.Name {
    static let messagingBlocksDidChange = Notification.Name("messagingBlocksDidChange")
}
