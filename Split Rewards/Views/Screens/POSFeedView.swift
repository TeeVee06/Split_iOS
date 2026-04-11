//
//  POSFeedView.swift
//  Split Rewards
//
// 
//

import SwiftUI

struct POSFeedView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var walletManager: WalletManager

    private let background = Color.black
    private let surface = Color.splitInputSurface

    @State private var isLoading = false
    @State private var hasAttemptedLoad = false
    @State private var hasLoadedResponse = false
    @State private var errorMessage: String?
    @State private var posts: [POSFeedPostRecord] = []
    @State private var zapPost: POSFeedPostRecord?
    @State private var selectedPosterPost: POSFeedPostRecord?
    @State private var postPendingReport: POSFeedPostRecord?
    @State private var reportingPostId: String?
    @State private var reportErrorMessage: String?
    @State private var showFeedHelp = false

    var body: some View {
        rootContent
            .task { await initialLoad() }
            .onAppear {
                if !hasLoadedResponse && !isLoading {
                    Task { await initialLoad() }
                }
            }
            .refreshable { await refresh() }
            .onReceive(NotificationCenter.default.publisher(for: .proofOfSpendPostDidCreate)) { _ in
                Task { await refresh() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .messagingBlocksDidChange)) { _ in
                Task { await refresh() }
            }
            .onChange(of: authManager.hasValidSession) { _, hasValidSession in
                guard hasValidSession, !hasLoadedResponse else { return }
                Task { await initialLoad() }
            }
            .onChange(of: authManager.state) { _, newState in
                guard newState == .authenticated, !hasLoadedResponse else { return }
                Task { await initialLoad() }
            }
            .confirmationDialog(
                "Report Post",
                isPresented: reportConfirmationBinding,
                titleVisibility: .visible,
                presenting: postPendingReport
            ) { post in
                Button("Report", role: .destructive) {
                    Task {
                        await report(post)
                    }
                }

                Button("Cancel", role: .cancel) {
                    postPendingReport = nil
                }
            } message: { _ in
                Text("Report this Proof of Spend post for review?")
            }
            .alert(
                "Unable to Report Post",
                isPresented: reportErrorBinding
            ) {
                Button("OK", role: .cancel) {
                    reportErrorMessage = nil
                }
            } message: {
                Text(reportErrorMessage ?? "")
            }
            .navigationDestination(item: $selectedPosterPost) { post in
                MessageParticipantDetailView(
                    title: posterTitle(for: post),
                    lightningAddress: post.posterLightningAddress,
                    walletPubkey: nil,
                    profilePicUrl: post.posterProfilePicUrl
                )
                .environmentObject(walletManager)
                .environmentObject(authManager)
            }
            .fullScreenCover(item: $zapPost) { post in
                SendToView(
                    prefilledRecipientInput: post.posterLightningAddress,
                    prefilledComment: "Zap for POS post"
                )
                .environmentObject(walletManager)
            }
            .sheet(isPresented: $showFeedHelp) {
                ProofOfSpendHelpSheet()
            }
    }

    private var rootContent: some View {
        ZStack {
            background
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 18)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        feedContent
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
                }
            }
        }
    }

    @ViewBuilder
    private var feedContent: some View {
        if !hasAttemptedLoad || isLoading || (!hasLoadedResponse && errorMessage == nil) {
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
                    postCard(for: post)
                }
            }
        }
    }

    private var reportConfirmationBinding: Binding<Bool> {
        Binding(
            get: { postPendingReport != nil },
            set: { newValue in
                if !newValue {
                    postPendingReport = nil
                }
            }
        )
    }

    private var reportErrorBinding: Binding<Bool> {
        Binding(
            get: { reportErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    reportErrorMessage = nil
                }
            }
        )
    }

    private func postCard(for post: POSFeedPostRecord) -> some View {
        let reportAction: (() -> Void)? = post.isOwnPostByViewer
            ? nil
            : {
                guard !post.isReportedByViewer else { return }
                postPendingReport = post
            }

        return ProofOfSpendPostCardView(
            authorLabel: post.posterLightningAddress,
            placeText: post.placeText,
            amountText: satsAmountText(for: post.amountSats),
            caption: post.caption,
            timestampText: relativeTimestamp(for: post.createdAt),
            profilePicUrl: post.posterProfilePicUrl,
            remotePhotoURLStrings: post.resolvedImageUrls,
            shareURL: publicPostURL(for: post),
            onAuthorTap: {
                selectedPosterPost = post
            },
            onReport: reportAction,
            isReported: post.isReportedByViewer,
            isReporting: reportingPostId == post.id,
            onZap: {
                zapPost = post
            },
            placeholderCopy: "Your posted photo will appear here"
        )
    }

    private var header: some View {
        HStack {
            Text("Proof of Spend")
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.white)

            Spacer(minLength: 16)

            Button {
                showFeedHelp = true
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 42, height: 42)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )

                    Image(systemName: "circle.rectangle.filled.pattern.diagonalline")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 2)
            .accessibilityLabel("How to post to the feed")
        }
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No posts yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)

            Text("Posts with a photo will show up here once you publish your first Proof of Spend.")
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
            Text("Unable to load the feed")
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
    private func initialLoad() async {
        await refresh()

        if !hasLoadedResponse && errorMessage == nil {
            for _ in 0..<2 {
                try? await Task.sleep(nanoseconds: 400_000_000)
                await refresh()
                if hasLoadedResponse || errorMessage != nil { break }
            }
        }
    }

    @MainActor
    private func refresh() async {
        if isLoading { return }

        hasAttemptedLoad = true
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            posts = try await GetPOSFeedPostsAPI.fetchPosts(
                authManager: authManager,
                walletManager: walletManager
            )
            hasLoadedResponse = true
        } catch is CancellationError {
            // Don't surface transient cancellation on first load.
        } catch let urlError as URLError where urlError.code == .cancelled {
            // Don't surface transient cancellation on first load.
        } catch {
            posts = []
            errorMessage = "Failed to load feed."
        }
    }

    @MainActor
    private func report(_ post: POSFeedPostRecord) async {
        guard reportingPostId == nil else { return }
        guard !post.isReportedByViewer else {
            postPendingReport = nil
            return
        }

        reportingPostId = post.id
        reportErrorMessage = nil
        defer {
            reportingPostId = nil
            postPendingReport = nil
        }

        do {
            let updatedPost = try await ReportPOSFeedPostAPI.reportPost(
                postId: post.id,
                authManager: authManager,
                walletManager: walletManager
            )

            if let index = posts.firstIndex(where: { $0.id == updatedPost.id }) {
                posts[index] = updatedPost
            }
        } catch {
            reportErrorMessage = error.localizedDescription
        }
    }

    private func satsAmountText(for sats: Int64) -> String {
        "\(NumberFormatter.localizedString(from: NSNumber(value: sats), number: .decimal)) sats"
    }

    private func posterTitle(for post: POSFeedPostRecord) -> String {
        let trimmed = post.posterLightningAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let atIndex = trimmed.firstIndex(of: "@"), atIndex > trimmed.startIndex else {
            return trimmed
        }

        return String(trimmed[..<atIndex])
    }

    private func relativeTimestamp(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func publicPostURL(for post: POSFeedPostRecord) -> URL? {
        URL(string: "\(AppConfig.baseURL)/proof-of-spend/\(post.id)")
    }
}

#Preview {
    POSFeedView()
}

private struct ProofOfSpendHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 18) {
                    Text("Proof of Spend exists to show how Bitcoin is being used in everyday life. It is a place to share experiences and help make the circular economy visible.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.76))
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Every Send transaction in your Transactions list includes a Feed icon. Tap that icon to create a post.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.76))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Text("Tap the")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white.opacity(0.62))

                        Image(systemName: "circle.rectangle.filled.pattern.diagonalline")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.splitBrandPink)

                        Text("in your transaction.")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white.opacity(0.62))
                    }

                    Spacer(minLength: 0)
                }
                .padding(20)
            }
            .navigationTitle("How to Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .presentationDetents([.height(300)])
    }
}
