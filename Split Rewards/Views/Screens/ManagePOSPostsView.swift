//
//  ManagePOSPostsView.swift
//  Split Rewards
//
//

import SwiftUI

struct ManagePOSPostsView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var walletManager: WalletManager

    private let background = Color.black
    private let surface = Color.splitInputSurface

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var posts: [POSFeedPostRecord] = []
    @State private var deletingPostId: String?
    @State private var postPendingDeletion: POSFeedPostRecord?

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    if isLoading {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 24)

                    } else if let errorMessage {
                        errorCard(errorMessage)

                    } else if posts.isEmpty {
                        emptyStateCard

                    } else {
                        LazyVStack(spacing: 16) {
                            ForEach(posts) { post in
                                ProofOfSpendPostCardView(
                                    authorLabel: post.posterLightningAddress,
                                    placeText: post.placeText,
                                    amountText: satsAmountText(for: post.amountSats),
                                    caption: post.caption,
                                    timestampText: relativeTimestamp(for: post.createdAt),
                                    profilePicUrl: post.posterProfilePicUrl,
                                    remotePhotoURLStrings: post.resolvedImageUrls,
                                    shareURL: publicPostURL(for: post),
                                    onDelete: {
                                        postPendingDeletion = post
                                    },
                                    placeholderCopy: "Your posted photo will appear here"
                                )
                                .opacity(deletingPostId == post.id ? 0.56 : 1)
                                .animation(.easeInOut(duration: 0.18), value: deletingPostId)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .refreshable { await refresh() }
        .alert(
            "Delete Post?",
            isPresented: Binding(
                get: { postPendingDeletion != nil },
                set: { newValue in
                    if !newValue {
                        postPendingDeletion = nil
                    }
                }
            ),
            presenting: postPendingDeletion
        ) { post in
            Button("Delete", role: .destructive) {
                Task { await delete(post) }
            }

            Button("Cancel", role: .cancel) {
                postPendingDeletion = nil
            }
        } message: { post in
            Text("This will remove your Proof of Spend post for \(resolvedPlaceText(for: post)) from the feed.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Proof of Spend")
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.white)

            Text("Manage your posts.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.62))
        }
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No posts yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)

            Text("Your Proof of Spend posts will show up here after you publish them from a completed transaction.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Unable to load your posts")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.red.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Task { await refresh() }
            } label: {
                Text("Retry")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    @MainActor
    private func refresh() async {
        isLoading = true
        errorMessage = nil

        do {
            posts = try await GetMyPOSFeedPostsAPI.fetchPosts(
                authManager: authManager,
                walletManager: walletManager
            )
        } catch {
            posts = []
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    @MainActor
    private func delete(_ post: POSFeedPostRecord) async {
        guard deletingPostId == nil else { return }

        deletingPostId = post.id
        defer {
            deletingPostId = nil
            postPendingDeletion = nil
        }

        do {
            try await DeletePOSFeedPostAPI.deletePost(
                postId: post.id,
                authManager: authManager,
                walletManager: walletManager
            )

            withAnimation(.easeInOut(duration: 0.2)) {
                posts.removeAll { $0.id == post.id }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func satsAmountText(for sats: Int64) -> String {
        "\(NumberFormatter.localizedString(from: NSNumber(value: sats), number: .decimal)) sats"
    }

    private func relativeTimestamp(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func publicPostURL(for post: POSFeedPostRecord) -> URL? {
        URL(string: "\(AppConfig.baseURL)/proof-of-spend/\(post.id)")
    }

    private func resolvedPlaceText(for post: POSFeedPostRecord) -> String {
        let trimmed = post.placeText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "this verified payment" : trimmed
    }
}

#Preview {
    NavigationStack {
        ManagePOSPostsView()
    }
}
