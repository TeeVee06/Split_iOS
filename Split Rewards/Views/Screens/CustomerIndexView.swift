//  CustomerIndexView.swift
//  Split
//
//
import SwiftUI
import SafariServices

struct CustomerIndexView: View {
    @EnvironmentObject var walletManager: WalletManager
    @EnvironmentObject var authManager: AuthManager

    let blue = Color.splitBrandBlue
    let pink = Color.splitBrandPink
    
    private let berry = Color.splitBerry
    private let indigo = Color.splitIndigo
    private let appBlack = Color.splitAppBlack
    private let cardSurface = Color.splitCardSurface
    private let hairline = Color.white.opacity(0.10)
    private let strongHairline = Color.white.opacity(0.16)

    @State private var isShowingRestoreSheet = false
    @State private var isShowingSeedBackup = false

    @State private var btcPriceUSD: Double? = nil
    @State private var isRefreshingBTCPrice: Bool = false

    @State private var onRampCoverItem: OnRampCoverItem? = nil
    @State private var isStartingOnRamp: Bool = false
    @State private var isShowingOnRampProviderPicker: Bool = false
    @State private var isShowingMoonPayAmountSheet: Bool = false

    @State private var isShowingBTCChart: Bool = false

    @State private var alertMessage: String? = nil

    private struct OnRampCoverItem: Identifiable {
        let id = UUID()
        let url: URL
    }

    private enum OnRampProvider {
        case stripe
        case moonPay
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                walletStateSection
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .onChange(of: walletManager.state) { _, newState in
            guard case .ready = newState else { return }
            Task { try? await authManager.ensureSession(walletManager: walletManager) }
            refreshBTCPrice()
        }
        .onAppear {
            if case .ready = walletManager.state {
                refreshBTCPrice()
            }
        }
        .sheet(isPresented: $isShowingRestoreSheet) {
            RestoreWalletView(isPresented: $isShowingRestoreSheet, pink: pink)
                .environmentObject(walletManager)
                .environmentObject(authManager)
        }
        .sheet(isPresented: $isShowingSeedBackup) {
            if !walletManager.pendingSeedWords.isEmpty {
                SeedPhraseBackupView(
                    words: walletManager.pendingSeedWords,
                    onConfirm: {
                        Task {
                            await walletManager.confirmPendingWalletCreation(authManager: authManager)
                            await MainActor.run { isShowingSeedBackup = false }

                            if case .ready = walletManager.state {
                                try? await authManager.ensureSession(walletManager: walletManager)
                            }
                            refreshBTCPrice()
                        }
                    },
                    onCancel: {
                        walletManager.cancelPendingWalletCreation()
                        isShowingSeedBackup = false
                    }
                )
            } else {
                VStack {
                    Text("No seed phrase available.")
                        .foregroundColor(.white)
                        .padding()

                    Button("Close") {
                        isShowingSeedBackup = false
                    }
                    .padding()
                }
                .background(appBlack.ignoresSafeArea())
            }
        }
        .fullScreenCover(item: $onRampCoverItem, onDismiss: {
            onRampCoverItem = nil
            refreshBTCPrice()
        }) { item in
            InAppSafariView(url: item.url)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $isShowingOnRampProviderPicker) {
            onRampProviderPickerSheet
        }
        .sheet(isPresented: $isShowingMoonPayAmountSheet) {
            MoonPayAmountSheet(
                btcUsdRate: btcPriceUSD ?? walletManager.btcUsdRate,
                isStarting: isStartingOnRamp,
                onStart: { lockedAmountSats, estimatedSpendAmountCents in
                    startMoonPayOnRamp(
                        lockedAmountSats: lockedAmountSats,
                        estimatedSpendAmountCents: estimatedSpendAmountCents
                    )
                },
                onCancel: {
                    isShowingMoonPayAmountSheet = false
                }
            )
            .presentationDetents([.height(560)])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $isShowingBTCChart) {
            if #available(iOS 16.0, *) {
                BitcoinPriceChartFullscreenView(initialRange: .day) {
                    isShowingBTCChart = false
                }
            } else {
                ZStack {
                    appBlack.ignoresSafeArea()

                    VStack(spacing: 12) {
                        Text("Chart requires iOS 16+")
                            .foregroundColor(.white)

                        Button("Close") {
                            isShowingBTCChart = false
                        }
                        .foregroundColor(.white)
                    }
                    .padding()
                }
            }
        }
        .alert(
            "Notice",
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { newValue in
                    if !newValue { alertMessage = nil }
                }
            )
        ) {
            Button("OK", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private var onRampProviderPickerSheet: some View {
        ZStack {
            appBlack
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Capsule()
                    .fill(Color.white.opacity(0.20))
                    .frame(width: 44, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)

                Text("Choose Bitcoin Provider")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)

                providerOptionButton(
                    provider: .stripe,
                    title: "Stripe",
                    subtitle: "Buy Bitcoin with Stripe.",
                    logoName: "StripeOnRampLogo",
                    logoHeight: 22,
                    accent: blue
                )

                providerOptionButton(
                    provider: .moonPay,
                    title: "MoonPay",
                    subtitle: "Buy Bitcoin with MoonPay.",
                    logoName: "MoonPayOnRampLogo",
                    logoHeight: 34,
                    accent: pink
                )

                Button("Cancel", role: .cancel) {
                    isShowingOnRampProviderPicker = false
                }
                .font(.headline)
                .foregroundColor(.white.opacity(0.80))
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .presentationDetents([.height(430)])
        .presentationDragIndicator(.hidden)
    }

    private func providerOptionButton(
        provider: OnRampProvider,
        title: String,
        subtitle: String,
        logoName: String,
        logoHeight: CGFloat,
        accent: Color
    ) -> some View {
        Button {
            isShowingOnRampProviderPicker = false
            switch provider {
            case .stripe:
                startStripeOnRamp()
            case .moonPay:
                isShowingMoonPayAmountSheet = true
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white)

                    Image(logoName)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 108, maxHeight: logoHeight)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                }
                .frame(width: 132, height: 72)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.white)

                    Text(subtitle)
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.70))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.62))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(cardSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(accent.opacity(0.45), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isStartingOnRamp)
        .opacity(isStartingOnRamp ? 0.65 : 1)
    }

    @ViewBuilder
    private var walletStateSection: some View {
        switch walletManager.state {

        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                    .tint(.white)

                Text("Loading wallet...")
                    .foregroundColor(.white.opacity(0.74))
                    .font(.footnote)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(hairline, lineWidth: 1)
            )
            .shadow(color: indigo.opacity(0.30), radius: 16, x: 0, y: 10)

        case .noWallet:
            VStack(alignment: .leading, spacing: 16) {
                Text("Set Up Your Wallet")
                    .font(.headline)
                    .foregroundColor(.white)

                Text("You can link an existing wallet with a seed phrase, or create a brand-new non-custodial wallet on this device.")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.72))

                Button {
                    isShowingRestoreSheet = true
                } label: {
                    Text("Link Existing Wallet (Restore)")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [indigo, blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(strongHairline, lineWidth: 1)
                        )
                }

                Button {
                    Task {
                        await walletManager.createWallet()
                        await MainActor.run {
                            if !walletManager.pendingSeedWords.isEmpty {
                                isShowingSeedBackup = true
                            }
                        }
                    }
                } label: {
                    Text("Create New Wallet")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [berry, pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(strongHairline, lineWidth: 1)
                        )
                }

                if let error = walletManager.lastErrorMessage {
                    ErrorBox(message: error)
                }
            }
            .padding()
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(hairline, lineWidth: 1)
            )
            .shadow(color: indigo.opacity(0.30), radius: 16, x: 0, y: 10)

        case .ready:
            let fiatText: String = {
                if let fiat = walletManager.fiatBalanceUSD {
                    return String(format: "$%.2f", fiat)
                } else {
                    return "$0.00"
                }
            }()

            let btcText = "₿ \(walletManager.formattedBTCBalance)"

            let (authText, isAuthError): (String?, Bool) = {
                switch authManager.state {
                case .authenticating:
                    return ("Verifying with server…", false)
                case .failed(let msg):
                    return ("Server auth failed: \(msg)", true)
                default:
                    return (nil, false)
                }
            }()

            let priceText: String = {
                guard let btcPriceUSD else { return "—" }
                return formatUSD(btcPriceUSD)
            }()

            UnifiedWalletSurface(
                blue: blue,
                pink: pink,
                fiatBalanceText: fiatText,
                btcBalanceText: btcText,
                isSyncing: walletManager.isSyncing,
                authStatusText: authText,
                authStatusIsError: isAuthError,
                btcPriceText: priceText,
                onRefreshBTCPrice: { refreshBTCPrice() },
                onTapBTCPrice: { isShowingBTCChart = true },
                onBuy: { isShowingOnRampProviderPicker = true }
            )

        case .error(let message):
            VStack(alignment: .leading, spacing: 12) {
                Text("Wallet Error")
                    .font(.headline)
                    .foregroundColor(.white)

                Text(message)
                    .font(.footnote)
                    .foregroundColor(.red)

                Button {
                    Task {
                        await walletManager.configure(authManager: authManager)
                    }
                } label: {
                    Text("Retry")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [indigo, blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(strongHairline, lineWidth: 1)
                        )
                }
            }
            .padding()
            .background(cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(hairline, lineWidth: 1)
            )
            .shadow(color: indigo.opacity(0.30), radius: 16, x: 0, y: 10)
        }
    }

    private func refreshBTCPrice() {
        guard !isRefreshingBTCPrice else { return }
        isRefreshingBTCPrice = true

        fetchBitcoinPriceUSD { price in
            btcPriceUSD = price
            isRefreshingBTCPrice = false
        } onError: { msg in
            isRefreshingBTCPrice = false
            print("BTC price fetch failed: \(msg)")
        }
    }

    private func formatUSD(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    private func startStripeOnRamp() {
        guard !isStartingOnRamp else { return }
        isStartingOnRamp = true

        Task {
            do {
                let btcAddress = try await walletManager.getOnchainReceiveAddress()

                postOnRamp(
                    walletManager: walletManager,
                    authManager: authManager,
                    btcAddress: btcAddress,
                    onSuccess: { url in
                        if #available(iOS 15.0, *) {
                            SFSafariViewController.prewarmConnections(to: [url])
                        }

                        onRampCoverItem = OnRampCoverItem(url: url)
                        isStartingOnRamp = false
                    },
                    onError: { msg in
                        alertMessage = msg
                        isStartingOnRamp = false
                    }
                )
            } catch {
                alertMessage = "Failed to generate on-chain address: \(error.localizedDescription)"
                isStartingOnRamp = false
            }
        }
    }

    private func startMoonPayOnRamp(lockedAmountSats: UInt64, estimatedSpendAmountCents: Int) {
        guard !isStartingOnRamp else { return }
        isStartingOnRamp = true

        postMoonPayPrepareBuy(
            walletManager: walletManager,
            authManager: authManager,
            lockedAmountSats: lockedAmountSats,
            estimatedSpendAmountCents: estimatedSpendAmountCents,
            onSuccess: { response in
                Task {
                    do {
                        let url = try await walletManager.createMoonPayBuyURL(
                            lockedAmountSat: response.lockedAmountSats,
                            redirectUrl: response.redirectUrl
                        )

                        if #available(iOS 15.0, *) {
                            SFSafariViewController.prewarmConnections(to: [url])
                        }

                        isShowingMoonPayAmountSheet = false
                        onRampCoverItem = OnRampCoverItem(url: url)
                        isStartingOnRamp = false
                    } catch {
                        alertMessage = "Failed to start MoonPay: \(error.localizedDescription)"
                        isStartingOnRamp = false
                    }
                }
            },
            onError: { msg in
                alertMessage = msg
                isStartingOnRamp = false
            }
        )
    }
}
