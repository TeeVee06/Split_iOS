//
//  OnChainAddress.swift
//  Split Rewards
//
//
import BreezSdkSpark

extension WalletManager {

    /// Returns a Bitcoin on-chain receive address suitable for Stripe onramp.
    func getOnchainReceiveAddress() async throws -> String {
        guard let sdk else {
            throw WalletError.sdkNotInitialized
        }

        let response = try await sdk.receivePayment(
            request: ReceivePaymentRequest(
                paymentMethod: ReceivePaymentMethod.bitcoinAddress
            )
        )
       
        print("🧪 SDK bitcoin receive address: \(response.paymentRequest)")

        // This is the BTC address string (bc1…)
        return response.paymentRequest
    }
}

