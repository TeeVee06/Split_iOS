//
//  UnifiedWalletSurface.swift
//  Split Rewards
//
//

import SwiftUI
import UIKit

struct UnifiedWalletSurface: View {
    @EnvironmentObject private var walletManager: WalletManager

    let blue: Color
    let pink: Color

    let fiatBalanceText: String
    let btcBalanceText: String

    let isSyncing: Bool
    let authStatusText: String?
    let authStatusIsError: Bool

    let btcPriceText: String
    let onRefreshBTCPrice: () -> Void
    let onTapBTCPrice: () -> Void
    let onBuy: () -> Void

    private let berry = Color.splitBerry

    @State private var showSendFlow = false
    @State private var showReceiveFlow = false
    @StateObject private var transactionActivityTracker = TransactionActivityTracker.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 16) {
                balanceHero
                actionRow
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.05),
                                Color.white.opacity(0.02),
                                Color.black.opacity(0.84)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 10)

            RampPriceCard(
                priceText: btcPriceText,
                onTapPrice: onTapBTCPrice,
                onRefreshPrice: onRefreshBTCPrice,
                onBuy: onBuy
            )
        }
        .fullScreenCover(isPresented: $showSendFlow) {
            NavigationStack {
                SendToView()
            }
        }
        .fullScreenCover(isPresented: $showReceiveFlow) {
            NavigationStack {
                ReceiveAmountView()
            }
        }
        .task {
            await refreshTransactionActivity()
        }
        .onReceive(NotificationCenter.default.publisher(for: .walletTransactionsDidChange)) { _ in
            Task {
                await refreshTransactionActivity()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task {
                await refreshTransactionActivity()
            }
        }
    }

    private var balanceHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(fiatBalanceText)
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer()
            }

            Text(btcBalanceText)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.84))
                .monospacedDigit()

            if isSyncing {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.white)

                    Text("Syncing…")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.82))
                }
            }

            if let authStatusText {
                Text(authStatusText)
                    .font(.caption)
                    .foregroundColor(authStatusIsError ? .red.opacity(0.95) : .white.opacity(0.82))
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 18)
        .background(
            ZStack {
                LinearGradient(
                    colors: [blue, pink],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                LinearGradient(
                    colors: [Color.white.opacity(0.16), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.30), lineWidth: 1)
        )
        .shadow(color: berry.opacity(0.22), radius: 22, x: 0, y: 12)
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                showSendFlow = true
            } label: {
                WalletActionPill(
                    icon: "arrow.up.right",
                    title: "Send",
                    background: Color.white.opacity(0.06),
                    tint: Color.white,
                    highlightColor: nil,
                    badgeCount: 0
                )
            }
            .buttonStyle(.plain)

            Button {
                showReceiveFlow = true
            } label: {
                WalletActionPill(
                    icon: "arrow.down.left",
                    title: "Receive",
                    background: Color.white.opacity(0.06),
                    tint: Color.white,
                    highlightColor: nil,
                    badgeCount: 0
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                TransactionsView()
            } label: {
                WalletActionPill(
                    icon: "arrow.left.arrow.right.circle.fill",
                    title: "Tx",
                    background: Color.white.opacity(0.06),
                    tint: Color.white,
                    highlightColor: blue,
                    badgeCount: transactionActivityTracker.unseenCount
                )
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    @MainActor
    private func refreshTransactionActivity() async {
        await transactionActivityTracker.refreshIfPossible(walletManager: walletManager)
    }

    private struct WalletActionPill: View {
        let icon: String
        let title: String
        let background: Color
        let tint: Color
        let highlightColor: Color?
        let badgeCount: Int

        private var isHighlighted: Bool {
            badgeCount > 0
        }

        private var badgeText: String {
            badgeCount > 9 ? "9+" : "\(badgeCount)"
        }

        var body: some View {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(tint)

                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            isHighlighted
                                ? (highlightColor ?? tint).opacity(0.80)
                                : Color.white.opacity(0.10),
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: isHighlighted
                        ? (highlightColor ?? tint).opacity(0.18)
                        : .clear,
                    radius: 10,
                    x: 0,
                    y: 4
                )

                if badgeCount > 0 {
                    Text(badgeText)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill((highlightColor ?? tint).opacity(0.92))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.20), lineWidth: 1)
                        )
                        .offset(x: 8, y: -8)
                }
            }
        }
    }
}
