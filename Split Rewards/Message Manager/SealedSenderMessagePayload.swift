//
//  SealedSenderMessagePayload.swift
//  Split Rewards
//
//

import Foundation

struct SealedSenderMessagePayload: Codable {
    let body: String
    let sender: MessagingIdentityBindingPayload
    let senderEnvelopeSignature: String
    let senderEnvelopeSignatureVersion: Int
}
