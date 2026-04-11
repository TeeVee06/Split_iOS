import SwiftUI

struct BlockedUsersView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var walletManager: WalletManager

    @State private var blockedUsers: [MessagingBlockedUser] = []
    @State private var contactNamesByLightningAddress: [String: String] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var inFlightUnblocks: Set<String> = []

    private let background = Color.black
    private let rowSurface = Color.splitInputSurface

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            Group {
                if isLoading {
                    loadingState
                } else if blockedUsers.isEmpty {
                    if let errorMessage {
                        errorState(message: errorMessage)
                    } else {
                        emptyState
                    }
                } else {
                    VStack(spacing: 0) {
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.subheadline)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                                .padding(.top, 12)
                        }

                        blockedList
                    }
                }
            }
        }
        .navigationTitle("Blocked Users")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            await loadData()
        }
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            Spacer()

            ProgressView()
                .tint(.white)
                .scaleEffect(1.1)

            Text("Loading Blocked Users")
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)

            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 88, height: 88)

                Image(systemName: "nosign")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
            }

            Text("No Blocked Users")
                .font(.title3.weight(.semibold))
                .foregroundColor(.white)

            Text("Anyone you block in messaging will appear here.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.splitBrandPink)

            Text("Unable to Load Blocks")
                .font(.title3.weight(.semibold))
                .foregroundColor(.white)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            Button("Try Again") {
                Task {
                    await loadData(forceReload: true)
                }
            }
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(Color.splitBrandPink)
            )
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private var blockedList: some View {
        List {
            ForEach(blockedUsers) { block in
                HStack(spacing: 12) {
                    avatarView(for: block)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayName(for: block))
                            .font(.headline.weight(.semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Text(secondaryText(for: block))
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.58))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 12)

                    if inFlightUnblocks.contains(block.blockedWalletPubkey) {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Button("Unblock") {
                            Task {
                                await unblock(block)
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.splitBrandPink)
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(rowSurface)
                )
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .environment(\.colorScheme, .dark)
    }

    private func avatarView(for block: MessagingBlockedUser) -> some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 50, height: 50)

            if let rawUrl = block.blockedProfilePicUrl,
               let url = URL(string: rawUrl),
               !rawUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Image(systemName: "nosign")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            } else {
                Image(systemName: "nosign")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
    }

    private func displayName(for block: MessagingBlockedUser) -> String {
        if let lightningAddress = block.normalizedLightningAddress,
           let contactName = contactNamesByLightningAddress[lightningAddress],
           !contactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return contactName
        }

        if let lightningAddress = block.normalizedLightningAddress {
            return lightningAddress
        }

        return abbreviatedWalletPubkey(block.blockedWalletPubkey)
    }

    private func secondaryText(for block: MessagingBlockedUser) -> String {
        if let lightningAddress = block.normalizedLightningAddress {
            return lightningAddress
        }

        return abbreviatedWalletPubkey(block.blockedWalletPubkey)
    }

    private func abbreviatedWalletPubkey(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 16 else { return trimmed }
        let prefix = trimmed.prefix(8)
        let suffix = trimmed.suffix(8)
        return "\(prefix)...\(suffix)"
    }

    @MainActor
    private func loadData(forceReload: Bool = false) async {
        if isLoading && !forceReload {
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let blocks = try await MessagingBlockAPI.fetchBlocks(
                authManager: authManager,
                walletManager: walletManager
            )
            let contacts = try await walletManager.listContacts()

            blockedUsers = blocks
            contactNamesByLightningAddress = Dictionary(
                uniqueKeysWithValues: contacts.map { contact in
                    (
                        contact.paymentIdentifier
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .lowercased(),
                        contact.name
                    )
                }
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    @MainActor
    private func unblock(_ block: MessagingBlockedUser) async {
        let walletPubkey = block.blockedWalletPubkey
        inFlightUnblocks.insert(walletPubkey)
        errorMessage = nil

        defer {
            inFlightUnblocks.remove(walletPubkey)
        }

        do {
            _ = try await MessagingBlockAPI.unblockUser(
                blockedWalletPubkey: walletPubkey,
                authManager: authManager,
                walletManager: walletManager
            )
            blockedUsers.removeAll { $0.blockedWalletPubkey == walletPubkey }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
