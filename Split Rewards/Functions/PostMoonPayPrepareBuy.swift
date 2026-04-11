import Foundation

struct MoonPayPrepareBuyResponse: Decodable {
    let redirectUrl: String
    let lockedAmountSats: UInt64
    let estimatedSpendAmountCents: Int
    let expiresAt: String
}

@MainActor
func postMoonPayPrepareBuy(
    walletManager: WalletManager,
    authManager: AuthManager,
    lockedAmountSats: UInt64,
    estimatedSpendAmountCents: Int,
    onSuccess: ((MoonPayPrepareBuyResponse) -> Void)? = nil,
    onError: ((String) -> Void)? = nil
) {
    Task {
        do {
            try await authManager.ensureSession(walletManager: walletManager)
        } catch {
            onError?("Authentication failed: \(error.localizedDescription)")
            return
        }

        guard let url = URL(string: "\(AppConfig.baseURL)/moonpay/prepare-buy") else {
            onError?("Invalid MoonPay URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpShouldHandleCookies = true

        struct RequestBody: Encodable {
            let lockedAmountSats: UInt64
            let estimatedSpendAmountCents: Int
        }

        do {
            request.httpBody = try JSONEncoder().encode(
                RequestBody(
                    lockedAmountSats: lockedAmountSats,
                    estimatedSpendAmountCents: estimatedSpendAmountCents
                )
            )
        } catch {
            onError?("Failed to encode MoonPay request.")
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    onError?("Network error while starting MoonPay: \(error.localizedDescription)")
                }
                return
            }

            guard let data else {
                DispatchQueue.main.async {
                    onError?("No data received from MoonPay prepare endpoint.")
                }
                return
            }

            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                let bodyString = String(data: data, encoding: .utf8) ?? "<non-UTF8 body>"
                print("MoonPay prepare server error \(httpResponse.statusCode): \(bodyString)")

                DispatchQueue.main.async {
                    onError?("Server error \(httpResponse.statusCode) while preparing MoonPay.")
                }
                return
            }

            do {
                let decoded = try JSONDecoder().decode(MoonPayPrepareBuyResponse.self, from: data)
                DispatchQueue.main.async {
                    onSuccess?(decoded)
                }
            } catch {
                let bodyString = String(data: data, encoding: .utf8) ?? "<non-UTF8 body>"
                print("MoonPay prepare decode error: \(error)")
                print("Raw response body: \(bodyString)")

                DispatchQueue.main.async {
                    onError?("Failed to decode MoonPay prepare response.")
                }
            }
        }
        .resume()
    }
}
