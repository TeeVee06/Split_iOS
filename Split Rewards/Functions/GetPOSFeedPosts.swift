//
//  GetPOSFeedPosts.swift
//  Split Rewards
//
//

import Foundation

struct POSFeedPostRecord: Decodable, Identifiable, Hashable {
    let id: String
    let posterUserId: String
    let posterLightningAddress: String
    let posterProfilePicUrl: String?
    let transactionId: String
    let amountSats: Int64
    let paidAt: Date?
    let placeText: String
    let caption: String
    let imageUrl: String
    let imageUrls: [String]?
    let imageObjectKey: String
    let imageObjectKeys: [String]?
    let reportCount: Int?
    let isFlagged: Bool?
    let viewerHasReported: Bool?
    let isOwnPost: Bool?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case posterUserId
        case posterLightningAddress
        case posterProfilePicUrl
        case transactionId
        case amountSats
        case paidAt
        case placeText
        case caption
        case imageUrl
        case imageUrls
        case imageObjectKey
        case imageObjectKeys
        case reportCount
        case isFlagged
        case viewerHasReported
        case isOwnPost
        case createdAt
    }

    var resolvedImageUrls: [String] {
        let normalized = (imageUrls ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if !normalized.isEmpty {
            return normalized
        }

        let single = imageUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return single.isEmpty ? [] : [single]
    }

    var normalizedReportCount: Int {
        max(reportCount ?? 0, 0)
    }

    var isReportedByViewer: Bool {
        viewerHasReported ?? false
    }

    var isOwnPostByViewer: Bool {
        isOwnPost ?? false
    }
}

struct POSFeedPostsEnvelope: Decodable {
    let posts: [POSFeedPostRecord]
}

private struct ReportPOSFeedPostResponse: Decodable {
    let ok: Bool?
    let didUpdate: Bool?
    let post: POSFeedPostRecord?
    let error: String?
}

enum POSFeedJSONDecoderFactory {
    static func make() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)

            if let date = fractional.date(from: raw) ?? plain.date(from: raw) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO-8601 date: \(raw)"
            )
        }
        return decoder
    }

    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

enum GetPOSFeedPostsAPI {
    @MainActor
    static func fetchPosts(
        limit: Int = 25,
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> [POSFeedPostRecord] {
        try await authManager.ensureSession(walletManager: walletManager)

        var components = URLComponents(string: "\(AppConfig.baseURL)/pos-feed/posts")
        components?.queryItems = [
            URLQueryItem(name: "limit", value: String(limit))
        ]

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = true

        var (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse,
           http.statusCode == 401 || http.statusCode == 403 {
            authManager.invalidateSession()
            try await authManager.ensureSession(walletManager: walletManager)
            (data, response) = try await URLSession.shared.data(for: request)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "GetPOSFeedPostsAPI",
                code: httpResponse.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        raw.isEmpty
                        ? "Server error (HTTP \(httpResponse.statusCode))"
                        : "Server error (HTTP \(httpResponse.statusCode)): \(raw)"
                ]
            )
        }

        return try POSFeedJSONDecoderFactory.make()
            .decode(POSFeedPostsEnvelope.self, from: data)
            .posts
    }
}

enum ReportPOSFeedPostError: LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid report post endpoint URL."
        case .invalidResponse:
            return "Invalid server response."
        case .serverError(_, let message):
            return message
        }
    }
}

enum ReportPOSFeedPostAPI {
    @MainActor
    static func reportPost(
        postId: String,
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> POSFeedPostRecord {
        guard let url = URL(string: "\(AppConfig.baseURL)/pos-feed/posts/\(postId)/report") else {
            throw ReportPOSFeedPostError.invalidURL
        }

        try await authManager.ensureSession(walletManager: walletManager)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse,
           http.statusCode == 401 || http.statusCode == 403 {
            authManager.invalidateSession()
            try await authManager.ensureSession(walletManager: walletManager)
            (data, response) = try await URLSession.shared.data(for: request)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ReportPOSFeedPostError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let serverMessage: String
            if let decoded = try? POSFeedJSONDecoderFactory.make().decode(ReportPOSFeedPostResponse.self, from: data),
               let error = decoded.error,
               !error.isEmpty {
                serverMessage = error
            } else {
                serverMessage = String(data: data, encoding: .utf8) ?? "Unknown server error"
            }

            throw ReportPOSFeedPostError.serverError(
                statusCode: httpResponse.statusCode,
                message: serverMessage
            )
        }

        guard let decoded = try? POSFeedJSONDecoderFactory.make().decode(ReportPOSFeedPostResponse.self, from: data),
              let post = decoded.post else {
            throw ReportPOSFeedPostError.invalidResponse
        }

        return post
    }
}
