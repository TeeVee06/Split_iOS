//
//  MainTemplateView.swift
//  Split Rewards
//
//

import SwiftUI

struct MainTemplateView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var walletManager: WalletManager
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var messagingNotificationRouter = MessagingNotificationRouter.shared

    @State private var selectedTab: NavBarView.Tab = .wallet
    @State private var liveMessageSyncTask: Task<Void, Never>?
    @State private var keyboardVisible = false

    private let liveMessageSyncIntervalNanoseconds: UInt64 = 2_000_000_000

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HeaderView()
                NavBarView(selectedTab: $selectedTab)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationBarBackButtonHidden(true)
        }
        .preferredColorScheme(.dark)
        .task {
            await syncMessagesIfPossible(force: true)
            await syncOutgoingStatusesIfPossible(force: true)
            startLiveMessageSyncLoop()
            activateMessagesTabIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await syncMessagesIfPossible(force: true)
                    await syncOutgoingStatusesIfPossible(force: true)
                }
                startLiveMessageSyncLoop()
            } else {
                liveMessageSyncTask?.cancel()
                liveMessageSyncTask = nil
            }
        }
        .onChange(of: messagingNotificationRouter.pendingRoute?.id) { _, _ in
            activateMessagesTabIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .proofOfSpendPostDidCreate)) { _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                selectedTab = .feed
            }
        }
        .onDisappear {
            liveMessageSyncTask?.cancel()
            liveMessageSyncTask = nil
        }
    }

    @MainActor
    private func syncMessagesIfPossible(force: Bool) async {
        guard case .ready = walletManager.state else { return }
        SharedOutgoingMessageRelayStore.importPendingMessages()
        await MessagingDeviceTokenManager.shared.syncDeviceTokenIfPossible(
            authManager: authManager,
            walletManager: walletManager,
            force: force
        )
        await MessageSyncManager.shared.syncInboxIfPossible(
            authManager: authManager,
            walletManager: walletManager,
            force: force
        )
        _ = await MessagingPushSyncCoordinator.shared.processPendingPushIfPossible()
    }

    @MainActor
    private func syncOutgoingStatusesIfPossible(force: Bool) async {
        guard case .ready = walletManager.state else { return }
        await MessageSyncManager.shared.syncOutgoingStatusesIfPossible(
            authManager: authManager,
            walletManager: walletManager,
            force: force
        )
        _ = await MessagingPushSyncCoordinator.shared.processPendingPushIfPossible()
    }

    @MainActor
    private func startLiveMessageSyncLoop() {
        liveMessageSyncTask?.cancel()

        liveMessageSyncTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: liveMessageSyncIntervalNanoseconds)
                guard !Task.isCancelled else { break }
                guard scenePhase == .active else { continue }
                guard !keyboardVisible else { continue }
                await syncMessagesIfPossible(force: true)
            }
        }
    }

    @MainActor
    private func activateMessagesTabIfNeeded() {
        if messagingNotificationRouter.pendingRoute != nil {
            selectedTab = .messages
        }
    }
}

struct MainTemplateView_Previews: PreviewProvider {
    static var previews: some View {
        MainTemplateView()
    }
}
