//  ShareCard.swift
//  Split Rewards
//
//
import SwiftUI
import UIKit
import PhotosUI

private struct ShareURLButton: View {
    let shareAction: () -> Void
    var isPreparing = false

    var body: some View {
        Button {
            shareAction()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 40, height: 40)

                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    .frame(width: 40, height: 40)

                if isPreparing {
                    ProgressView()
                        .tint(.white.opacity(0.82))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "paperplane.circle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white.opacity(0.82))
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .disabled(isPreparing)
    }
}

private struct ZapPostButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "bolt.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Color.splitBrandPink)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(Color.splitBrandPink.opacity(0.14))
                )
                .overlay(
                    Circle()
                        .stroke(Color.splitBrandPink.opacity(0.24), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
    }
}

private struct DeletePostButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.red.opacity(0.95))
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(Color.red.opacity(0.12))
                )
                .overlay(
                    Circle()
                        .stroke(Color.red.opacity(0.20), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
    }
}

private struct ReportPostButton: View {
    let action: () -> Void
    var isReported = false
    var isReporting = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isReported ? Color.splitBrandPink.opacity(0.14) : Color.white.opacity(0.06))
                    .frame(width: 36, height: 36)

                Circle()
                    .stroke(
                        isReported ? Color.splitBrandPink.opacity(0.30) : Color.white.opacity(0.08),
                        lineWidth: 1
                    )
                    .frame(width: 36, height: 36)

                if isReporting {
                    ProgressView()
                        .tint(isReported ? .splitBrandPink : .white.opacity(0.82))
                        .scaleEffect(0.72)
                } else {
                    Image(systemName: isReported ? "flag.fill" : "flag")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isReported ? .splitBrandPink : .white.opacity(0.82))
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .disabled(isReporting || isReported)
    }
}

// MARK: - Share Composer

struct ProofOfSpendShareComposer: View {
    let tx: WalletManager.TransactionRow
    let onPostCreated: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var walletManager: WalletManager

    @FocusState private var focusedField: ComposerField?
    @State private var selectedPreviewPhotoIndex = 0
    @State private var editingPhotoTarget: ProofOfSpendPhotoAdjustmentTarget?
    @State private var hasPostingLightningAddress = false
    @State private var isLoadingPostingLightningAddress = false
    @State private var postingEligibilityError: String?

    @ObservedObject var draft: ProofOfSpendComposerDraft

    private let surface = Color.splitInputSurface
    private let secondarySurface = Color.splitInputSurfaceSecondary
    private let accentPink = Color.splitBrandPink
    private let previewAnchorID = "proof-of-spend-preview-anchor"

    private var selectedPreviewMediaIndexBinding: Binding<Int> {
        Binding(
            get: {
                let count = max(draft.attachedPhotos.count, 1)
                return min(selectedPreviewPhotoIndex, count - 1)
            },
            set: { newValue in
                selectedPreviewPhotoIndex = max(0, newValue)
            }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.opacity(0.95)
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismissKeyboard()
                    }

                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        composerContent
                        .padding(.horizontal, 16)
                        .padding(.top, 18)
                        .padding(.bottom, 24)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: draft.attachedPhotos.count) { oldCount, newCount in
                        if newCount > oldCount {
                            DispatchQueue.main.async {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    proxy.scrollTo(previewAnchorID, anchor: .top)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(.white.opacity(0.85))
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if focusedField != nil {
                    HStack {
                        Spacer()

                        Button("Done") {
                            dismissKeyboard()
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(accentPink)
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.92))
                }
            }
            .sheet(isPresented: $draft.isPickingPhoto) {
                MultiImagePicker(
                    images: $draft.attachedPhotos,
                    maxSelectionCount: draft.remainingPhotoSlots
                )
                    .ignoresSafeArea()
            }
            .sheet(item: $editingPhotoTarget) { target in
                if draft.attachedPhotos.indices.contains(target.index) {
                    ProofOfSpendPhotoAdjustmentView(
                        image: draft.attachedPhotos[target.index],
                        onSave: { adjustedImage in
                            draft.replacePhoto(at: target.index, with: adjustedImage)
                            selectedPreviewPhotoIndex = target.index
                        }
                    )
                }
            }
            .onChange(of: draft.attachedPhotos.count) { _, newCount in
                if newCount == 0 {
                    selectedPreviewPhotoIndex = 0
                    editingPhotoTarget = nil
                } else if selectedPreviewPhotoIndex >= newCount {
                    selectedPreviewPhotoIndex = max(0, newCount - 1)
                }
            }
            .task {
                await refreshPostingEligibility()
            }
        }
    }

    private var composerContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Color.clear
                .frame(height: 1)
                .id(previewAnchorID)

            Text("Create Proof of Spend")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)

            previewCardSection
            adjustPhotoSection
            composerFormSection
        }
    }

    private var previewCardSection: some View {
        ProofOfSpendPostCardView(
            authorLabel: "Your Proof of Spend",
            placeText: resolvedPlaceText,
            amountText: "",
            caption: draft.captionText,
            timestampText: tx.dateString,
            localPhotos: draft.attachedPhotos,
            selectedMediaIndexOverride: selectedPreviewMediaIndexBinding,
            placeholderCopy: "Add photos to create your post"
        )
    }

    @ViewBuilder
    private var adjustPhotoSection: some View {
        if !draft.attachedPhotos.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    guard draft.attachedPhotos.indices.contains(selectedPreviewPhotoIndex) else { return }
                    editingPhotoTarget = ProofOfSpendPhotoAdjustmentTarget(index: selectedPreviewPhotoIndex)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "crop")
                            .font(.system(size: 15, weight: .semibold))

                        Text("Adjust photo to fit post")
                            .font(.system(size: 15, weight: .semibold))

                        Spacer(minLength: 0)

                        Text("Photo \(selectedPreviewPhotoIndex + 1)")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white.opacity(0.54))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(secondarySurface)
                    )
                }
                .buttonStyle(.plain)

                Text("Preview the post, then adjust any photo if the crop feels off.")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.54))
            }
        }
    }

    private var composerFormSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            addPhotosButton

            if draft.attachedPhotos.isEmpty {
                Text("At least one photo is required to create a Proof of Spend post.")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.58))
            } else {
                photoThumbnailStrip
            }

            Text("Up to 4 photos. The first photo becomes the main card image.")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.54))

            if let postingRequirementMessage {
                Text(postingRequirementMessage)
                    .font(.footnote)
                    .foregroundColor(postingEligibilityError == nil ? .white.opacity(0.64) : .red.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let submissionError = draft.submissionError {
                Text(submissionError)
                    .font(.footnote)
                    .foregroundColor(.red.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
            }

            placeField
            captionField
            postButton
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black.opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var addPhotosButton: some View {
        Button {
            if draft.remainingPhotoSlots > 0 {
                draft.isPickingPhoto = true
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: draft.attachedPhotos.isEmpty ? "camera.fill" : "photo.on.rectangle.angled")
                    .font(.system(size: 15, weight: .semibold))

                Text(photoButtonTitle)
                    .font(.system(size: 15, weight: .semibold))

                Spacer(minLength: 0)

                Text("\(draft.attachedPhotos.count)/4")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.54))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(secondarySurface)
            )
        }
        .buttonStyle(.plain)
        .disabled(draft.remainingPhotoSlots == 0)
    }

    private var placeField: some View {
        VStack(alignment: .leading, spacing: 8) {
            editorLabel("Place")

            TextField("Where did you spend it?", text: $draft.placeText)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(false)
                .focused($focusedField, equals: .place)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(surface)
                )
                .foregroundColor(.white)
        }
    }

    private var captionField: some View {
        VStack(alignment: .leading, spacing: 8) {
            editorLabel("Caption")

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(surface)

                if draft.captionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Write a caption")
                        .foregroundColor(.white.opacity(0.34))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                }

                TextEditor(text: $draft.captionText)
                    .focused($focusedField, equals: .caption)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(minHeight: 138)
                    .foregroundColor(.white)
                    .background(Color.clear)
            }
            .frame(minHeight: 138)
        }
    }

    private var postButton: some View {
        Button {
            Task { await submitPost() }
        } label: {
            HStack(spacing: 10) {
                if draft.isSubmitting {
                    ProgressView()
                        .tint(.black)
                }

                Text(draft.isSubmitting ? "Posting..." : "Post")
                    .font(.system(size: 16, weight: .semibold))
            }
            .font(.system(size: 16, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(canPost ? Color.white : Color.white.opacity(0.10))
            .foregroundColor(canPost ? .black : .white.opacity(0.34))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canPost)
    }

    private var canPost: Bool {
        !draft.attachedPhotos.isEmpty
            && !draft.isSubmitting
            && !isLoadingPostingLightningAddress
            && hasPostingLightningAddress
    }

    @MainActor
    private func submitPost() async {
        guard !draft.isSubmitting else { return }
        guard !draft.attachedPhotos.isEmpty else { return }

        draft.submissionError = nil
        focusedField = nil

        await refreshPostingEligibility()
        guard hasPostingLightningAddress else {
            if let postingEligibilityError {
                draft.submissionError = postingEligibilityError
            } else {
                draft.submissionError = "A Lightning address is required to create a Proof of Spend post. Create one in Profile first."
            }
            return
        }

        draft.isSubmitting = true

        defer {
            draft.isSubmitting = false
        }

        let uploadImages = draft.attachedPhotos.enumerated().compactMap { index, image -> POSFeedPostUploadImage? in
            guard let imageData = image.jpegData(compressionQuality: 0.88) else {
                return nil
            }

            return POSFeedPostUploadImage(
                data: imageData,
                fileName: "proof-of-spend-\(index + 1).jpg",
                mimeType: "image/jpeg"
            )
        }

        guard uploadImages.count == draft.attachedPhotos.count else {
            draft.submissionError = "Could not prepare one of the selected photos."
            return
        }

        do {
            _ = try await PostPOSFeedPostAPI.createPost(
                transactionId: tx.id,
                amountSats: tx.amountSats,
                paidAt: tx.transactionDate,
                placeText: resolvedPlaceText == "Verified payment" ? "" : resolvedPlaceText,
                caption: draft.captionText.trimmingCharacters(in: .whitespacesAndNewlines),
                images: uploadImages,
                authManager: authManager,
                walletManager: walletManager
            )

            onPostCreated?()
            NotificationCenter.default.post(name: .proofOfSpendPostDidCreate, object: tx.id)
            dismiss()
        } catch {
            draft.submissionError = error.localizedDescription
        }
    }

    private var resolvedPlaceText: String {
        let trimmed = draft.placeText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Verified payment" : trimmed
    }

    private var postingRequirementMessage: String? {
        if isLoadingPostingLightningAddress {
            return "Checking Lightning address..."
        }

        if let postingEligibilityError {
            return postingEligibilityError
        }

        guard !hasPostingLightningAddress else {
            return nil
        }

        return "A Lightning address is required to create a Proof of Spend post. Create one in Profile first."
    }

    @MainActor
    private func refreshPostingEligibility() async {
        if isLoadingPostingLightningAddress {
            return
        }

        isLoadingPostingLightningAddress = true
        postingEligibilityError = nil

        defer {
            isLoadingPostingLightningAddress = false
        }

        do {
            let lightningAddressInfo = try await walletManager.fetchLightningAddress()
            hasPostingLightningAddress = lightningAddressInfo != nil
        } catch {
            hasPostingLightningAddress = false
            postingEligibilityError = error.localizedDescription
        }
    }

    private func dismissKeyboard() {
        focusedField = nil
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func editorLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundColor(.white.opacity(0.60))
    }

    private var photoButtonTitle: String {
        if draft.attachedPhotos.isEmpty {
            return "Add Photos"
        }

        if draft.remainingPhotoSlots > 0 {
            return "Add More Photos"
        }

        return "Photo Limit Reached"
    }

    private var photoThumbnailStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(draft.attachedPhotos.enumerated()), id: \.offset) { index, image in
                    ZStack(alignment: .topTrailing) {
                        Button {
                            selectedPreviewPhotoIndex = index
                        } label: {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(
                                            selectedPreviewPhotoIndex == index
                                                ? Color.splitBrandPink
                                                : Color.white.opacity(0.12),
                                            lineWidth: selectedPreviewPhotoIndex == index ? 2 : 1
                                        )
                                )
                        }
                        .buttonStyle(.plain)

                        Button {
                            draft.removePhoto(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                                .background(Circle().fill(Color.black.opacity(0.72)))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 6, y: -6)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct ProofOfSpendPhotoAdjustmentTarget: Identifiable {
    let index: Int
    var id: Int { index }
}

private enum ComposerField: Hashable {
    case place
    case caption
}

@MainActor
final class ProofOfSpendComposerDraft: ObservableObject {
    @Published var attachedPhotos: [UIImage] = []
    @Published var isPickingPhoto = false
    @Published var placeText: String
    @Published var captionText: String = ""
    @Published var submissionError: String?
    @Published var isSubmitting = false

    init(placeText: String) {
        self.placeText = placeText
    }

    func reset(placeText: String) {
        attachedPhotos = []
        isPickingPhoto = false
        self.placeText = placeText
        captionText = ""
        submissionError = nil
        isSubmitting = false
    }

    var remainingPhotoSlots: Int {
        max(0, 4 - attachedPhotos.count)
    }

    func removePhoto(at index: Int) {
        guard attachedPhotos.indices.contains(index) else { return }
        attachedPhotos.remove(at: index)
    }

    func replacePhoto(at index: Int, with image: UIImage) {
        guard attachedPhotos.indices.contains(index) else { return }
        attachedPhotos[index] = image
    }
}

// MARK: - Card View

struct ProofOfSpendPostCardView: View {
    @State private var sharePayload: ProofOfSpendSharePayload?
    @State private var isPreparingShare = false
    @State private var internalSelectedMediaIndex = 0

    let authorLabel: String
    let placeText: String
    let amountText: String
    let caption: String
    let timestampText: String
    var profilePicUrl: String? = nil
    var renderedProfileImage: UIImage? = nil
    var localPhoto: UIImage? = nil
    var localPhotos: [UIImage] = []
    var remotePhotoURLString: String? = nil
    var remotePhotoURLStrings: [String] = []
    var renderedRemotePhoto: UIImage? = nil
    var renderedRemotePhotos: [UIImage] = []
    var selectedMediaIndexOverride: Binding<Int>? = nil
    var shareURL: URL? = nil
    var onAuthorTap: (() -> Void)? = nil
    var onReport: (() -> Void)? = nil
    var isReported = false
    var isReporting = false
    var onZap: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var photoHeight: CGFloat = 300
    var placeholderCopy: String = "Your photo will anchor this post"
    var showsActionButtons: Bool = true

    private let accentPink = Color.splitBrandPink
    private let accentBlue = Color.splitBrandBlue
    private let cardSurface = Color.splitInputSurfaceTertiary

    private var selectedMediaIndexBinding: Binding<Int> {
        if let selectedMediaIndexOverride {
            return selectedMediaIndexOverride
        }

        return $internalSelectedMediaIndex
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                authorIdentityView

                Spacer(minLength: 0)

                Text(timestampText)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.50))
                    .multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 16)

            mediaView

            VStack(alignment: .leading, spacing: 12) {
                Text(resolvedPlaceText)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .allowsTightening(true)
                    .fixedSize(horizontal: false, vertical: true)

                if !trimmedCaption.isEmpty {
                    Text(trimmedCaption)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }

                actionButtons
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 18)
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(cardSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .sheet(item: $sharePayload) { payload in
            URLShareSheet(items: payload.items)
                .ignoresSafeArea()
        }
    }

    private var displayAuthorLabel: String {
        let trimmed = authorLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let atIndex = trimmed.firstIndex(of: "@"), atIndex > trimmed.startIndex else {
            return trimmed
        }

        return String(trimmed[..<atIndex])
    }

    @ViewBuilder
    private var authorIdentityView: some View {
        if let onAuthorTap {
            Button(action: onAuthorTap) {
                authorIdentityLabel
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityLabel("Open poster details")
        } else {
            authorIdentityLabel
        }
    }

    private var authorIdentityLabel: some View {
        HStack(alignment: .center, spacing: 12) {
            avatarView

            VStack(alignment: .leading, spacing: 3) {
                Text(displayAuthorLabel)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text("Proof of Spend")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.56))
            }
        }
    }

    private var mediaView: some View {
        ZStack(alignment: .topTrailing) {
            if mediaSources.isEmpty {
                placeholderMedia
            } else if !showsActionButtons {
                mediaPageView(for: mediaSources[0])
            } else if mediaSources.count == 1 {
                mediaPageView(for: mediaSources[0])
            } else {
                TabView(selection: selectedMediaIndexBinding) {
                    ForEach(Array(mediaSources.enumerated()), id: \.offset) { index, source in
                        mediaPageView(for: source)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
            }

            if mediaSources.count > 1 {
                Text(mediaCountLabel)
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.62))
                    )
                    .padding(12)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: photoHeight)
        .clipped()
    }

    @ViewBuilder
    private func mediaPageView(for source: ProofOfSpendCardMediaSource) -> some View {
        switch source {
        case .image(let image):
            Image(uiImage: image)
                .resizable()
                .scaledToFill()

        case .remote(let rawUrl):
            if let url = URL(string: rawUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()

                    default:
                        placeholderMedia
                    }
                }
            } else {
                placeholderMedia
            }
        }
    }

    private var placeholderMedia: some View {
        ZStack {
            LinearGradient(
                colors: [
                    accentBlue.opacity(0.28),
                    accentPink.opacity(0.24),
                    Color.black.opacity(0.88)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 10) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white.opacity(0.88))

                Text(placeholderCopy)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
    }

    private var avatarView: some View {
        Group {
            if let renderedProfileImage {
                Image(uiImage: renderedProfileImage)
                    .resizable()
                    .scaledToFill()
            } else if let profilePicUrl,
               let url = URL(string: profilePicUrl),
               !profilePicUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()

                    default:
                        fallbackAvatar
                    }
                }
            } else {
                fallbackAvatar
            }
        }
        .frame(width: 42, height: 42)
        .clipShape(Circle())
    }

    private var fallbackAvatar: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [accentBlue.opacity(0.88), accentPink.opacity(0.88)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
            }
    }

    private var resolvedPlaceText: String {
        let trimmed = placeText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Verified payment" : trimmed
    }

    private var trimmedCaption: String {
        caption.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var effectiveLocalPhotos: [UIImage] {
        if !localPhotos.isEmpty {
            return localPhotos
        }

        if let localPhoto {
            return [localPhoto]
        }

        return []
    }

    private var effectiveRenderedRemotePhotos: [UIImage] {
        if !renderedRemotePhotos.isEmpty {
            return renderedRemotePhotos
        }

        if let renderedRemotePhoto {
            return [renderedRemotePhoto]
        }

        return []
    }

    private var normalizedRemotePhotoURLs: [String] {
        let normalized = remotePhotoURLStrings
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if !normalized.isEmpty {
            return normalized
        }

        if let remotePhotoURLString {
            let trimmed = remotePhotoURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return [trimmed]
            }
        }

        return []
    }

    private var mediaSources: [ProofOfSpendCardMediaSource] {
        if !effectiveRenderedRemotePhotos.isEmpty {
            return effectiveRenderedRemotePhotos.map { .image($0) }
        }

        if !effectiveLocalPhotos.isEmpty {
            return effectiveLocalPhotos.map { .image($0) }
        }

        if !normalizedRemotePhotoURLs.isEmpty {
            return normalizedRemotePhotoURLs.map { .remote($0) }
        }

        return []
    }

    private var mediaCountLabel: String {
        if showsActionButtons {
            return "\(min(selectedMediaIndexBinding.wrappedValue + 1, mediaSources.count))/\(mediaSources.count)"
        }

        return "1/\(mediaSources.count)"
    }

    @ViewBuilder
    private var actionButtons: some View {
        if showsActionButtons {
            HStack(spacing: 10) {
                if let onReport {
                    ReportPostButton(
                        action: onReport,
                        isReported: isReported,
                        isReporting: isReporting
                    )
                    .accessibilityLabel(isReported ? "Post reported" : "Report post")
                }

                Spacer(minLength: 0)

                if shareURL != nil {
                    ShareURLButton(
                        shareAction: {
                            Task { await presentShareCard() }
                        },
                        isPreparing: isPreparingShare
                    )
                } else {
                    Image(systemName: "circle.rectangle.filled.pattern.diagonalline")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(accentPink.opacity(0.86))
                }

                if let onZap {
                    ZapPostButton(action: onZap)
                }

                if let onDelete {
                    DeletePostButton(action: onDelete)
                }
            }
            .zIndex(1)
            .contentShape(Rectangle())
        }
    }

    @MainActor
    private func presentShareCard() async {
        guard !isPreparingShare else { return }
        isPreparingShare = true
        defer { isPreparingShare = false }

        let profileImage = await loadImage(from: profilePicUrl)
        let remotePhotos = effectiveRenderedRemotePhotos.isEmpty
            ? await loadImages(from: normalizedRemotePhotoURLs)
            : effectiveRenderedRemotePhotos
        let image = renderShareImage(
            profileImage: profileImage,
            remotePhotos: remotePhotos
        )

        if let fileURL = image.writeProofOfSpendPNGToTemporaryFile(prefix: "split-proof-spend") {
            sharePayload = ProofOfSpendSharePayload(items: [fileURL])
        } else {
            sharePayload = ProofOfSpendSharePayload(items: [image])
        }
    }

    private func renderShareImage(profileImage: UIImage?, remotePhotos: [UIImage]) -> UIImage {
        ProofOfSpendPostShareExportCard(
            authorLabel: authorLabel,
            placeText: placeText,
            amountText: amountText,
            caption: caption,
            timestampText: timestampText,
            renderedProfileImage: profileImage,
            localPhotos: effectiveLocalPhotos,
            renderedRemotePhotos: remotePhotos,
            photoHeight: photoHeight,
            placeholderCopy: placeholderCopy
        )
        .frame(width: 360, height: 640)
        .renderAsImage(size: CGSize(width: 360, height: 640))
    }

    private func loadImage(from rawUrl: String?) async -> UIImage? {
        guard let rawUrl,
              !rawUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: rawUrl) else {
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }

    private func loadImages(from rawUrls: [String]) async -> [UIImage] {
        var images: [UIImage] = []

        for rawUrl in rawUrls {
            if let image = await loadImage(from: rawUrl) {
                images.append(image)
            }
        }

        return images
    }
}

private struct ProofOfSpendPostShareExportCard: View {
    let authorLabel: String
    let placeText: String
    let amountText: String
    let caption: String
    let timestampText: String
    let renderedProfileImage: UIImage?
    let localPhotos: [UIImage]
    let renderedRemotePhotos: [UIImage]
    let photoHeight: CGFloat
    let placeholderCopy: String

    var body: some View {
        ZStack {
            Color.black

            ProofOfSpendPostCardView(
                authorLabel: authorLabel,
                placeText: placeText,
                amountText: amountText,
                caption: caption,
                timestampText: timestampText,
                renderedProfileImage: renderedProfileImage,
                localPhotos: localPhotos,
                renderedRemotePhotos: renderedRemotePhotos,
                photoHeight: photoHeight,
                placeholderCopy: placeholderCopy,
                showsActionButtons: false
            )
            .padding(20)
        }
    }
}

private struct ProofOfSpendSharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

private enum ProofOfSpendCardMediaSource {
    case image(UIImage)
    case remote(String)
}

private struct ProofOfSpendCropLayout {
    let imagePixelSize: CGSize
    let cropSize: CGSize
    let zoomScale: CGFloat
    let offset: CGSize

    private var baseScale: CGFloat {
        max(
            cropSize.width / max(imagePixelSize.width, 1),
            cropSize.height / max(imagePixelSize.height, 1)
        )
    }

    var displayScale: CGFloat {
        baseScale * zoomScale
    }

    var displayedSize: CGSize {
        CGSize(
            width: imagePixelSize.width * displayScale,
            height: imagePixelSize.height * displayScale
        )
    }

    private var maxOffsetX: CGFloat {
        max(0, (displayedSize.width - cropSize.width) / 2)
    }

    private var maxOffsetY: CGFloat {
        max(0, (displayedSize.height - cropSize.height) / 2)
    }

    func clamp(_ proposedOffset: CGSize) -> CGSize {
        CGSize(
            width: min(max(proposedOffset.width, -maxOffsetX), maxOffsetX),
            height: min(max(proposedOffset.height, -maxOffsetY), maxOffsetY)
        )
    }

    var clampedOffset: CGSize {
        clamp(offset)
    }
}

private struct ProofOfSpendPhotoAdjustmentView: View {
    @Environment(\.dismiss) private var dismiss

    private let workingImage: UIImage
    private let onSave: (UIImage) -> Void
    private let targetAspectRatio: CGFloat = 6 / 5

    @State private var zoomScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastZoomScale: CGFloat = 1
    @State private var lastOffset: CGSize = .zero

    init(image: UIImage, onSave: @escaping (UIImage) -> Void) {
        self.workingImage = image.normalizedProofOfSpendImage()
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let horizontalPadding: CGFloat = 24
                let cropWidth = max(geometry.size.width - (horizontalPadding * 2), 1)
                let cropHeight = cropWidth / targetAspectRatio
                let cropSize = CGSize(width: cropWidth, height: cropHeight)
                let layout = currentLayout(cropSize: cropSize)

                ZStack {
                    Color.black
                        .ignoresSafeArea()

                    VStack(alignment: .leading, spacing: 18) {
                        Text("Adjust photo to fit post")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)

                        Text("Drag to reframe and pinch to zoom. This controls how the photo fills the post card.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.70))
                            .fixedSize(horizontal: false, vertical: true)

                        ZStack {
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .fill(Color.splitInputSurfaceTertiary)

                            Image(uiImage: workingImage)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: layout.displayedSize.width, height: layout.displayedSize.height)
                                .offset(layout.clampedOffset)
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            let proposed = CGSize(
                                                width: lastOffset.width + value.translation.width,
                                                height: lastOffset.height + value.translation.height
                                            )
                                            offset = currentLayout(cropSize: cropSize).clamp(proposed)
                                        }
                                        .onEnded { value in
                                            let proposed = CGSize(
                                                width: lastOffset.width + value.translation.width,
                                                height: lastOffset.height + value.translation.height
                                            )
                                            offset = currentLayout(cropSize: cropSize).clamp(proposed)
                                            lastOffset = offset
                                        }
                                )
                                .simultaneousGesture(
                                    MagnificationGesture()
                                        .onChanged { value in
                                            let nextZoomScale = min(max(lastZoomScale * value, 1), 4)
                                            zoomScale = nextZoomScale
                                            offset = currentLayout(cropSize: cropSize).clamp(offset)
                                        }
                                        .onEnded { value in
                                            zoomScale = min(max(lastZoomScale * value, 1), 4)
                                            lastZoomScale = zoomScale
                                            offset = currentLayout(cropSize: cropSize).clamp(offset)
                                            lastOffset = offset
                                        }
                                )
                        }
                        .frame(width: cropWidth, height: cropHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                        .frame(maxWidth: .infinity)

                        HStack(spacing: 12) {
                            Button("Reset") {
                                zoomScale = 1
                                lastZoomScale = 1
                                offset = .zero
                                lastOffset = .zero
                            }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white.opacity(0.88))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.08))
                            )

                            Spacer()

                            Button("Save Fit") {
                                guard let croppedImage = workingImage.croppedProofOfSpendImage(
                                    cropSize: cropSize,
                                    zoomScale: zoomScale,
                                    offset: currentLayout(cropSize: cropSize).clampedOffset
                                ) else {
                                    dismiss()
                                    return
                                }

                                onSave(croppedImage)
                                dismiss()
                            }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(
                                Capsule()
                                    .fill(Color.white)
                            )
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 24)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white.opacity(0.84))
                }
            }
        }
    }

    private func currentLayout(cropSize: CGSize) -> ProofOfSpendCropLayout {
        ProofOfSpendCropLayout(
            imagePixelSize: workingImage.proofOfSpendPixelSize,
            cropSize: cropSize,
            zoomScale: zoomScale,
            offset: offset
        )
    }
}

// MARK: - UIKit Helpers

struct MultiImagePicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    @Binding var images: [UIImage]
    let maxSelectionCount: Int

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = max(1, maxSelectionCount)

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let parent: MultiImagePicker
        init(_ parent: MultiImagePicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !results.isEmpty else {
                parent.dismiss()
                return
            }

            Task {
                var loadedImages: [UIImage] = []

                for result in results {
                    if let image = await loadImage(from: result) {
                        loadedImages.append(image)
                    }
                }

                await MainActor.run {
                    parent.images.append(contentsOf: loadedImages)
                    if parent.images.count > 4 {
                        parent.images = Array(parent.images.prefix(4))
                    }
                    parent.dismiss()
                }
            }
        }

        private func loadImage(from result: PHPickerResult) async -> UIImage? {
            await withCheckedContinuation { continuation in
                guard result.itemProvider.canLoadObject(ofClass: UIImage.self) else {
                    continuation.resume(returning: nil)
                    return
                }

                result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                    continuation.resume(returning: object as? UIImage)
                }
            }
        }
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    @Binding var image: UIImage?

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]
        ) {
            if let selected = info[.originalImage] as? UIImage {
                parent.image = selected
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

private struct URLShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private extension UIImage {
    var proofOfSpendPixelSize: CGSize {
        if let cgImage {
            return CGSize(width: cgImage.width, height: cgImage.height)
        }

        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    func normalizedProofOfSpendImage() -> UIImage {
        guard imageOrientation != .up else { return self }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale

        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func croppedProofOfSpendImage(
        cropSize: CGSize,
        zoomScale: CGFloat,
        offset: CGSize
    ) -> UIImage? {
        let normalized = normalizedProofOfSpendImage()
        guard let cgImage = normalized.cgImage else { return nil }

        let layout = ProofOfSpendCropLayout(
            imagePixelSize: CGSize(width: cgImage.width, height: cgImage.height),
            cropSize: cropSize,
            zoomScale: zoomScale,
            offset: offset
        )

        let clampedOffset = layout.clampedOffset
        let originX = ((cropSize.width - layout.displayedSize.width) / 2) + clampedOffset.width
        let originY = ((cropSize.height - layout.displayedSize.height) / 2) + clampedOffset.height

        let cropRect = CGRect(
            x: (0 - originX) / layout.displayScale,
            y: (0 - originY) / layout.displayScale,
            width: cropSize.width / layout.displayScale,
            height: cropSize.height / layout.displayScale
        )
        .integral
        .intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))

        guard !cropRect.isNull,
              cropRect.width > 1,
              cropRect.height > 1,
              let croppedCGImage = cgImage.cropping(to: cropRect) else {
            return nil
        }

        return UIImage(cgImage: croppedCGImage, scale: normalized.scale, orientation: .up)
    }

    func writeProofOfSpendPNGToTemporaryFile(prefix: String) -> URL? {
        guard let data = pngData() else { return nil }
        let filename = "\(prefix)-\(UUID().uuidString).png"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try data.write(to: url, options: [.atomic])
            return url
        } catch {
            return nil
        }
    }
}

extension View {
    func renderAsImage(size: CGSize) -> UIImage {
        if #available(iOS 16.0, *) {
            // ImageRenderer is far more reliable than drawHierarchy for SwiftUI views.
            let renderer = ImageRenderer(content: self.frame(width: size.width, height: size.height))
            renderer.scale = UIScreen.main.scale
            return renderer.uiImage ?? UIImage()
        } else {
            let controller = UIHostingController(rootView: self)
            controller.view.bounds = CGRect(origin: .zero, size: size)
            controller.view.backgroundColor = .clear
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()

            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
        }
    }
}

extension Notification.Name {
    static let proofOfSpendPostDidCreate = Notification.Name("proofOfSpendPostDidCreate")
}
