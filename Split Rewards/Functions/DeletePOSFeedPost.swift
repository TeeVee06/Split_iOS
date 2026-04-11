//
//  DeletePOSFeedPost.swift
//  Split Rewards
//
//

import Foundation

enum DeletePOSFeedPostAPI {
    @MainActor
    static func deletePost(
        postId: String,
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws {
        try await authManager.ensureSession(walletManager: walletManager)

        guard let url = URL(string: "\(AppConfig.baseURL)/pos-feed/posts/\(postId)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
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
                domain: "DeletePOSFeedPostAPI",
                code: httpResponse.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        raw.isEmpty
                        ? "Server error (HTTP \(httpResponse.statusCode))"
                        : "Server error (HTTP \(httpResponse.statusCode)): \(raw)"
                ]
            )
        }
    }
}
