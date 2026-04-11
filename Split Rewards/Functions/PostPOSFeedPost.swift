//
//  PostPOSFeedPost.swift
//  Split Rewards
//
//

import Foundation

private struct CreatePOSFeedPostResponse: Decodable {
    let post: POSFeedPostRecord?
    let error: String?
}

struct POSFeedPostUploadImage {
    let data: Data
    let fileName: String
    let mimeType: String
}

enum PostPOSFeedPostError: LocalizedError {
    case invalidURL
    case emptyImageData
    case invalidResponse
    case serverError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Proof of Spend post endpoint URL."
        case .emptyImageData:
            return "At least one photo is required to create a post."
        case .invalidResponse:
            return "Invalid server response."
        case .serverError(_, let message):
            return message
        }
    }
}

enum PostPOSFeedPostAPI {
    @MainActor
    static func createPost(
        transactionId: String,
        amountSats: Int64,
        paidAt: Date?,
        placeText: String,
        caption: String,
        images: [POSFeedPostUploadImage],
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> POSFeedPostRecord {
        let normalizedImages = images.filter { !$0.data.isEmpty }
        guard !normalizedImages.isEmpty else {
            throw PostPOSFeedPostError.emptyImageData
        }

        guard let url = URL(string: "\(AppConfig.baseURL)/pos-feed/posts") else {
            throw PostPOSFeedPostError.invalidURL
        }

        try await authManager.ensureSession(walletManager: walletManager)

        let boundary = "Boundary-\(UUID().uuidString)"
        let paidAtString = paidAt.map { iso8601Formatter.string(from: $0) } ?? ""

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = makeMultipartBody(
            transactionId: transactionId,
            amountSats: amountSats,
            paidAt: paidAtString,
            placeText: placeText,
            caption: caption,
            images: normalizedImages,
            boundary: boundary
        )

        var (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse,
           http.statusCode == 401 || http.statusCode == 403 {
            authManager.invalidateSession()
            try await authManager.ensureSession(walletManager: walletManager)

            request.httpBody = makeMultipartBody(
                transactionId: transactionId,
                amountSats: amountSats,
                paidAt: paidAtString,
                placeText: placeText,
                caption: caption,
                images: normalizedImages,
                boundary: boundary
            )

            (data, response) = try await URLSession.shared.data(for: request)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PostPOSFeedPostError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let serverMessage: String
            if let decoded = try? JSONDecoder().decode(CreatePOSFeedPostResponse.self, from: data),
               let error = decoded.error,
               !error.isEmpty {
                serverMessage = error
            } else {
                serverMessage = String(data: data, encoding: .utf8) ?? "Unknown server error"
            }

            throw PostPOSFeedPostError.serverError(
                statusCode: httpResponse.statusCode,
                message: serverMessage
            )
        }

        guard let decoded = try? POSFeedJSONDecoderFactory.make().decode(CreatePOSFeedPostResponse.self, from: data),
              let post = decoded.post else {
            throw PostPOSFeedPostError.invalidResponse
        }

        return post
    }

    private static func makeMultipartBody(
        transactionId: String,
        amountSats: Int64,
        paidAt: String,
        placeText: String,
        caption: String,
        images: [POSFeedPostUploadImage],
        boundary: String
    ) -> Data {
        var body = Data()

        appendFormField(name: "transactionId", value: transactionId, to: &body, boundary: boundary)
        appendFormField(name: "amountSats", value: String(amountSats), to: &body, boundary: boundary)
        appendFormField(name: "paidAt", value: paidAt, to: &body, boundary: boundary)
        appendFormField(name: "placeText", value: placeText, to: &body, boundary: boundary)
        appendFormField(name: "caption", value: caption, to: &body, boundary: boundary)

        for image in images {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"images\"; filename=\"\(image.fileName)\"\r\n")
            body.append("Content-Type: \(image.mimeType)\r\n\r\n")
            body.append(image.data)
            body.append("\r\n")
        }

        body.append("--\(boundary)--\r\n")

        return body
    }

    private static func appendFormField(
        name: String,
        value: String,
        to body: inout Data,
        boundary: String
    ) {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        body.append(value)
        body.append("\r\n")
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
