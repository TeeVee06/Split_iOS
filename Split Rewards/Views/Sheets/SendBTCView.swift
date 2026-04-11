//
//  SendBTCView.swift
//  Split Rewards
//
//

import SwiftUI

struct SendBTCView: View {
    let onExitFlow: (() -> Void)?

    init(onExitFlow: (() -> Void)? = nil) {
        self.onExitFlow = onExitFlow
    }

    var body: some View {
        SendPaymentFlowView(
            startMode: .scan,
            onExitFlow: onExitFlow
        )
    }
}
