import Foundation
import BreezSdkSpark

extension WalletManager {
    func createMoonPayBuyURL(
        lockedAmountSat: UInt64? = nil,
        redirectUrl: String? = nil
    ) async throws -> URL {
        guard let sdk else {
            throw WalletError.sdkNotInitialized
        }

        let response = try await sdk.buyBitcoin(
            request: BuyBitcoinRequest(
                lockedAmountSat: lockedAmountSat,
                redirectUrl: redirectUrl
            )
        )

        guard let url = URL(string: response.url) else {
            throw URLError(.badURL)
        }

        return url
    }
}
