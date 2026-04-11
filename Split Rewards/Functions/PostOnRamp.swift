//  PostOnRamp.swift
//  Split Rewards
//
//  Creates a Stripe-hosted crypto onramp session
//  and returns the redirect URL for in-app browser launch
//

import Foundation

// MARK: - Response Model

struct OnRampResponse: Decodable {
    let onrampSessionId: String?
    let redirectUrl: String
    let status: String?
}

// MARK: - API Call (AUTHENTICATED)

/// Starts a Stripe-hosted crypto onramp session for the authenticated user.
/// The server returns a redirectUrl which should be opened in an in-app browser.
///
/// This endpoint is USER-IDENTITY dependent and therefore ensures
/// a valid server session via AuthManager.
@MainActor
func postOnRamp(
    walletManager: WalletManager,
    authManager: AuthManager,

    /// Bitcoin on-chain receive address to lock in Stripe hosted onramp.
    /// This should be a valid BTC address string (e.g., bc1...).
    btcAddress: String,

    onSuccess: ((URL) -> Void)? = nil,
    onError: ((String) -> Void)? = nil
) {
    Task {
        do {
            // 🔐 Ensure authenticated wallet session
            try await authManager.ensureSession(walletManager: walletManager)
        } catch {
            onError?("Authentication failed: \(error.localizedDescription)")
            return
        }

        guard let url = URL(string: "\(AppConfig.baseURL)/BuyRamp") else {
            onError?("Invalid BuyRamp URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpShouldHandleCookies = true

        struct RequestBody: Encodable {
            let btcAddress: String
        }

        do {
            request.httpBody = try JSONEncoder().encode(RequestBody(btcAddress: btcAddress))
        } catch {
            onError?("Failed to encode onramp request.")
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    onError?("Network error while starting onramp: \(error.localizedDescription)")
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    onError?("No data received from onramp server.")
                }
                return
            }

            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {

                let bodyString = String(data: data, encoding: .utf8) ?? "<non-UTF8 body>"
                print("Onramp server error \(httpResponse.statusCode): \(bodyString)")

                DispatchQueue.main.async {
                    onError?("Server error \(httpResponse.statusCode) while starting onramp.")
                }
                return
            }

            do {
                let decoded = try JSONDecoder().decode(OnRampResponse.self, from: data)

                guard let redirect = URL(string: decoded.redirectUrl) else {
                    DispatchQueue.main.async {
                        onError?("Invalid redirect URL returned from server.")
                    }
                    return
                }

                DispatchQueue.main.async {
                    onSuccess?(redirect)
                }
            } catch {
                let bodyString = String(data: data, encoding: .utf8) ?? "<non-UTF8 body>"
                print("Onramp decode error: \(error)")
                print("Raw response body: \(bodyString)")

                DispatchQueue.main.async {
                    onError?("Failed to decode onramp response.")
                }
            }
        }
        .resume()
    }
}



