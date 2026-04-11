//
//  PostRewardOnRampBuy.swift
//  Split Rewards
//
//
import Foundation

// MARK: - Response Model

struct RewardOnRampBuyResponse: Decodable {
    let ok: Bool
    let rewardSpendApplied: Bool
    let rewardSource: String?
}

// MARK: - API Call (AUTHENTICATED)

/// Call this after the user claims an on-chain deposit.
/// Sends the deposit txid and amount to the backend so it can apply
/// provider-specific onramp reward logic.
@MainActor
func postRewardOnRampBuy(
    walletManager: WalletManager,
    authManager: AuthManager,

    txid: String,
    depositAmountSats: UInt64? = nil,

    onSuccess: ((RewardOnRampBuyResponse) -> Void)? = nil,
    onError: ((String) -> Void)? = nil
) {
    Task {
        do {
            // 🔐 Ensure we have a valid wallet-authenticated session
            try await authManager.ensureSession(walletManager: walletManager)
        } catch {
            onError?("Authentication failed: \(error.localizedDescription)")
            return
        }

        guard let url = URL(string: "\(AppConfig.baseURL)/reward_onRamp_buy") else {
            onError?("Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpShouldHandleCookies = true

        struct RequestBody: Encodable {
            let txid: String
            let depositAmountSats: UInt64?
        }

        let body = RequestBody(txid: txid, depositAmountSats: depositAmountSats)

        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            onError?("Failed to encode onramp reward request.")
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    onError?("Network error while posting onramp reward: \(error.localizedDescription)")
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    onError?("No data received from server.")
                }
                return
            }

            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {

                let bodyString = String(data: data, encoding: .utf8) ?? "<non-UTF8 body>"
                print("Onramp reward server error \(httpResponse.statusCode): \(bodyString)")

                DispatchQueue.main.async {
                    onError?("Server error \(httpResponse.statusCode) while posting onramp reward.")
                }
                return
            }

            do {
                let decoded = try JSONDecoder().decode(RewardOnRampBuyResponse.self, from: data)
                DispatchQueue.main.async {
                    onSuccess?(decoded)
                }
            } catch {
                let bodyString = String(data: data, encoding: .utf8) ?? "<non-UTF8 body>"
                print("Onramp reward decode error: \(error)")
                print("Raw response body: \(bodyString)")

                DispatchQueue.main.async {
                    onError?("Failed to decode onramp reward response.")
                }
            }
        }
        .resume()
    }
}
