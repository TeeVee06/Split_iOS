//
//  Split_RewardsApp.swift
//  Split Rewards
//
//

import SwiftUI

@main
struct Split_RewardsApp: App {
    @UIApplicationDelegateAdaptor(SplitRewardsAppDelegate.self) private var appDelegate

    @StateObject private var walletManager = WalletManager()
    @StateObject private var authManager = AuthManager()   // ✅ ADD THIS
    @StateObject private var toastManager = ToastManager()
    @StateObject private var appState = AppState()

    @State private var isLoading = true
    @State private var isVersionValid = true

    // MARK: - App version check (unchanged)

    private func checkAppVersion() {
        guard let url = URL(string: "\(AppConfig.baseURL)/rewards-version-check") else {
            print("Invalid version check URL")
            isVersionValid = true
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Version check error: \(error.localizedDescription)")
                    isVersionValid = true
                    return
                }

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let minimumVersion = json["minimumVersion"] as? String else {
                    print("Invalid version check response")
                    isVersionValid = true
                    return
                }

                let currentVersion =
                    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"

                isVersionValid = compareVersions(currentVersion, minimumVersion)
            }
        }.resume()
    }

    private func compareVersions(_ current: String, _ required: String) -> Bool {
        let currentComponents = current.split(separator: ".").compactMap { Int($0) }
        let requiredComponents = required.split(separator: ".").compactMap { Int($0) }

        for (c, r) in zip(currentComponents, requiredComponents) {
            if c < r { return false }
            if c > r { return true }
        }
        return currentComponents.count >= requiredComponents.count
    }

    // MARK: - App body

    var body: some Scene {
        WindowGroup {
            ZStack(alignment: .top) {
                NavigationStack {
                    if isLoading {
                        ProgressView()
                    } else if !isVersionValid {
                        ForcedUpdateView()
                    } else {
                        MainTemplateView()
                    }
                }
                .task {
                    checkAppVersion()

                    // ✅ FIX: authManager now exists in this scope
                    await walletManager.configure(authManager: authManager)

                    isLoading = false
                }

                ToastView()
                    .padding(.top, 0)
            }
            .onAppear {
                walletManager.toastManager = toastManager
                MessagingPushSyncCoordinator.shared.configure(
                    authManager: authManager,
                    walletManager: walletManager
                )
                MessagingDeviceTokenManager.shared.registerForRemoteNotifications()
                Task { @MainActor in
                    _ = await MessagingPushSyncCoordinator.shared.processPendingPushIfPossible()
                }
            }
            .environmentObject(walletManager)
            .environmentObject(authManager)   // ✅ OPTIONAL but recommended
            .environmentObject(toastManager)
            .environmentObject(appState)
        }
    }
}





