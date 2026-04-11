//
//  GetMyPOSFeedPosts.swift
//  Split Rewards
//
//

import Foundation

enum GetMyPOSFeedPostsAPI {
    @MainActor
    static func fetchPosts(
        limit: Int = 50,
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> [POSFeedPostRecord] {
        try await authManager.ensureSession(walletManager: walletManager)

        var components = URLComponents(string: "\(AppConfig.baseURL)/pos-feed/my-posts")
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
                domain: "GetMyPOSFeedPostsAPI",
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
