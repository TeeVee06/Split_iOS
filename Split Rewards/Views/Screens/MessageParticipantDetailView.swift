import SwiftUI

struct MessageParticipantDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var walletManager: WalletManager
    @EnvironmentObject private var authManager: AuthManager

    let title: String
    let lightningAddress: String
    let walletPubkey: String?
    let initialProfilePicUrl: String?

    @State private var savedContact: WalletManager.WalletContact?
    @State private var resolvedRecipient: MessagingRecipient?
    @State private var activeBlock: MessagingBlockedUser?
    @State private var profilePicUrl: String
    @State private var showPaymentFlow = false
    @State private var isUpdatingBlockState = false
    @State private var blockActionError: String?
    @State private var showBlockConfirmation = false
    @State private var showUnblockConfirmation = false

    private let background = Color.black
    private let actionSurface = Color.splitInputSurface

    init(
        title: String,
        lightningAddress: String,
        walletPubkey: String?,
        savedContact: WalletManager.WalletContact? = nil,
        profilePicUrl: String? = nil
    ) {
        self.title = title
        self.lightningAddress = lightningAddress
        self.walletPubkey = walletPubkey
        self.initialProfilePicUrl = profilePicUrl
        _savedContact = State(initialValue: savedContact)
        _profilePicUrl = State(initialValue: profilePicUrl ?? "")
    }

    private var displayTitle: String {
        if let savedContact {
            return savedContact.name
        }
        return title
    }

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                Spacer()

                VStack(spacing: 12) {
                    if hasProfilePic, let url = URL(string: profilePicUrl) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            default:
                                EmptyView()
                            }
                        }
                        .frame(width: 104, height: 104)
                        .clipShape(Circle())
                    }

                    Text(displayTitle)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text(lightningAddress)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.62))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)

                HStack(spacing: 20) {
                    paymentActionButton
                    blockActionButton

                    if savedContact == nil {
                        NavigationLink(
                            destination: CreateContactView(
                                paymentIdentifier: lightningAddress,
                                onSaved: {
                                    Task {
                                        await refreshSavedContact()
                                    }
                                }
                            )
                        ) {
                            iconActionLabel(systemName: "plus")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add contact")
                    }
                }
                .padding(.top, 28)
                .padding(.horizontal, 20)

                if let blockActionError {
                    Text(blockActionError)
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                }

                Spacer()
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("Block User", isPresented: $showBlockConfirmation, titleVisibility: .visible) {
            Button("Block", role: .destructive) {
                Task {
                    await blockCurrentUser()
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They won’t be able to message you, and you won’t be able to message them until you unblock them.")
        }
        .confirmationDialog("Unblock User", isPresented: $showUnblockConfirmation, titleVisibility: .visible) {
            Button("Unblock") {
                Task {
                    await unblockCurrentUser()
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will let you message each other again.")
        }
        .task(id: lightningAddress) {
            await refreshScreenState()
        }
        .fullScreenCover(isPresented: $showPaymentFlow) {
            NavigationStack {
                SendToView(prefilledRecipientInput: lightningAddress)
            }
            .environmentObject(walletManager)
        }
    }

    private var header: some View {
        HStack {
            Button(action: { dismiss() }) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.semibold))

                    Text("Back")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)

            Spacer()

            if let savedContact {
                NavigationLink(
                    destination: EditContactView(
                        contact: savedContact,
                        onUpdated: { updated in
                            self.savedContact = updated
                        },
                        onDeleted: {
                            self.savedContact = nil
                        }
                    )
                ) {
                    Text("Edit")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    private var hasProfilePic: Bool {
        !profilePicUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func iconActionLabel(
        systemName: String,
        foregroundColor: Color = .white
    ) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 24, weight: .semibold))
            .foregroundColor(foregroundColor)
            .frame(width: 64, height: 64)
            .background(
                Circle()
                    .fill(actionSurface)
            )
    }

    private var paymentActionButton: some View {
        Button {
            showPaymentFlow = true
        } label: {
            iconActionLabel(systemName: "bolt.fill")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Payment options")
    }

    private var blockActionButton: some View {
        Button {
            blockActionError = nil
            if activeBlock == nil {
                showBlockConfirmation = true
            } else {
                showUnblockConfirmation = true
            }
        } label: {
            iconActionLabel(
                systemName: "nosign",
                foregroundColor: activeBlock == nil ? .white : .splitBrandPink
            )
            .overlay {
                if isUpdatingBlockState {
                    ProgressView()
                        .tint(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isUpdatingBlockState)
        .accessibilityLabel(activeBlock == nil ? "Block user" : "Unblock user")
    }

    @MainActor
    private func refreshScreenState() async {
        blockActionError = nil
        await refreshSavedContact()
        await refreshBlockState()

        guard activeBlock == nil else {
            resolvedRecipient = nil
            profilePicUrl = activeBlock?.blockedProfilePicUrl?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? initialProfilePicUrl ?? ""
            return
        }

        await refreshRecipient()
    }

    @MainActor
    private func refreshSavedContact() async {
        do {
            savedContact = try await walletManager.contact(forPaymentIdentifier: lightningAddress)
        } catch {
            savedContact = nil
        }
    }

    @MainActor
    private func refreshRecipient() async {
        do {
            let recipient = try await ResolveMessageRecipientAPI.resolveRecipient(
                lightningAddress: lightningAddress,
                authManager: authManager,
                walletManager: walletManager
            )
            resolvedRecipient = recipient
            profilePicUrl = recipient.profilePicUrl?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? initialProfilePicUrl ?? ""
        } catch {
            resolvedRecipient = nil
            if activeBlock == nil {
                profilePicUrl = initialProfilePicUrl ?? ""
            }
        }
    }

    @MainActor
    private func refreshBlockState() async {
        let normalizedLightningAddress = lightningAddress
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        do {
            let blocks = try await MessagingBlockAPI.fetchBlocks(
                authManager: authManager,
                walletManager: walletManager
            )
            activeBlock = blocks.first(where: { block in
                if let walletPubkey,
                   block.blockedWalletPubkey == walletPubkey {
                    return true
                }

                return block.normalizedLightningAddress == normalizedLightningAddress
            })
        } catch {
            activeBlock = nil
        }
    }

    @MainActor
    private func blockCurrentUser() async {
        isUpdatingBlockState = true
        blockActionError = nil

        do {
            let block = try await MessagingBlockAPI.blockUser(
                walletPubkey: resolvedRecipient?.walletPubkey ?? walletPubkey,
                lightningAddress: lightningAddress,
                authManager: authManager,
                walletManager: walletManager
            )
            activeBlock = block
            resolvedRecipient = nil
            profilePicUrl = block.blockedProfilePicUrl?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? profilePicUrl
        } catch {
            blockActionError = error.localizedDescription
        }

        isUpdatingBlockState = false
    }

    @MainActor
    private func unblockCurrentUser() async {
        guard let blockedWalletPubkey = activeBlock?.blockedWalletPubkey else {
            return
        }

        isUpdatingBlockState = true
        blockActionError = nil

        do {
            _ = try await MessagingBlockAPI.unblockUser(
                blockedWalletPubkey: blockedWalletPubkey,
                authManager: authManager,
                walletManager: walletManager
            )
            activeBlock = nil
            await refreshRecipient()
        } catch {
            blockActionError = error.localizedDescription
        }

        isUpdatingBlockState = false
    }
}
