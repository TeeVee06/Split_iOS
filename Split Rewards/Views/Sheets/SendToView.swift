//
//  SendToView.swift
//  Split Rewards
//
//

import SwiftUI

struct SendToView: View {
    let prefilledRecipientInput: String
    let prefilledComment: String?
    let onExitFlow: (() -> Void)?

    init(
        prefilledRecipientInput: String = "",
        prefilledComment: String? = nil,
        onExitFlow: (() -> Void)? = nil
    ) {
        self.prefilledRecipientInput = prefilledRecipientInput
        self.prefilledComment = prefilledComment
        self.onExitFlow = onExitFlow
    }

    var body: some View {
        SendPaymentFlowView(
            startMode: .entry(prefilledRecipientInput: prefilledRecipientInput),
            prefilledLnurlComment: prefilledComment,
            onExitFlow: onExitFlow
        )
    }
}
