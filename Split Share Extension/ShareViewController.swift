//
//  ShareViewController.swift
//  Split Share Extension
//
//

import AVFoundation
import SwiftUI
import UIKit

final class ShareViewController: UIViewController {
    private let viewModel = ShareMessageExtensionViewModel()
    private var hostingController: UIHostingController<ShareExtensionRootView>?

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear
        viewModel.configure(extensionContext: extensionContext)

        let rootView = ShareExtensionRootView(viewModel: viewModel)
        let hostingController = UIHostingController(rootView: rootView)
        hostingController.view.backgroundColor = .clear

        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        hostingController.didMove(toParent: self)
        self.hostingController = hostingController

        viewModel.loadPayload()
    }
}

private struct ShareExtensionRootView: View {
    @ObservedObject var viewModel: ShareMessageExtensionViewModel
    @FocusState private var focusedField: Field?

    private enum Field {
        case recipient
        case message
    }

    private let pageBackground = Color(uiColor: .systemGroupedBackground)
    private let cardBackground = Color.white
    private let separator = Color(uiColor: .separator)
    private let tint = Color(red: 0.00, green: 0.48, blue: 1.00)

    var body: some View {
        ZStack {
            pageBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if viewModel.isLoading {
                    loadingState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            recipientComposer

                            if let payload = viewModel.payload {
                                composerSection(for: payload)
                            }

                            if let errorMessage = viewModel.errorMessage, !errorMessage.isEmpty {
                                errorBanner(message: errorMessage)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .preferredColorScheme(.light)
        .onAppear {
            updateFocus()
        }
        .onChange(of: viewModel.selectedRecipient?.lightningAddress) { _, _ in
            updateFocus()
        }
        .onChange(of: viewModel.payload?.id) { _, _ in
            updateFocus()
        }
    }

    private var header: some View {
        HStack {
            Button("Cancel") {
                viewModel.cancel()
            }
            .font(.body)
            .foregroundColor(tint)

            Spacer()

            Text("New Message")
                .font(.headline.weight(.semibold))
                .foregroundColor(.black)

            Spacer()

            Button(action: {
                viewModel.sendDirectly()
            }) {
                if viewModel.isSending {
                    ProgressView()
                        .tint(tint)
                } else {
                    Text("Send")
                        .font(.body.weight(.semibold))
                }
            }
            .foregroundColor(viewModel.canSendDirectly ? tint : .gray)
            .disabled(!viewModel.canSendDirectly)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(
            Rectangle()
                .fill(Color(uiColor: .systemBackground))
                .overlay(alignment: .bottom) {
                    separator
                        .frame(height: 0.5)
                }
        )
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            Spacer()

            ProgressView()
                .tint(tint)
                .scaleEffect(1.05)

            Text("Preparing your share")
                .font(.headline.weight(.semibold))
                .foregroundColor(.black)

            Text("Loading the content and your recent Split recipients.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recipientComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Text("To:")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.black)
                    .padding(.top, 14)

                VStack(alignment: .leading, spacing: 10) {
                    if let selectedRecipient = viewModel.selectedRecipient {
                        RecipientChip(recipient: selectedRecipient) {
                            viewModel.clearSelectedRecipient()
                        }
                    } else {
                        TextField(
                            "Name or Lightning Address",
                            text: Binding(
                                get: { viewModel.recipientQuery },
                                set: { viewModel.setRecipientQuery($0) }
                            )
                        )
                        .focused($focusedField, equals: .recipient)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .submitLabel(.done)
                        .foregroundColor(.black)
                    }

                    if let selectedRecipient = viewModel.selectedRecipient {
                        Text(selectedRecipient.lightningAddress)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(cardBackground)
            )

            if viewModel.showsRecipientSuggestions {
                recipientSuggestionsDropdown
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: viewModel.showsRecipientSuggestions)
    }

    private var recipientSuggestionsDropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(viewModel.recipientSuggestions) { recipient in
                Button(action: {
                    viewModel.selectRecipient(recipient)
                }) {
                    HStack(spacing: 12) {
                        RecipientAvatar(profilePicURL: recipient.profilePicURL)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(recipient.displayName)
                                .font(.body.weight(.medium))
                                .foregroundColor(.black)
                                .lineLimit(1)

                            Text(recipient.lightningAddress)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)

                if recipient.id != viewModel.recipientSuggestions.last?.id {
                    separator
                        .frame(height: 0.5)
                        .padding(.leading, 62)
                }
            }

            if let typedRecipientCandidate = viewModel.typedRecipientCandidate {
                if !viewModel.recipientSuggestions.isEmpty {
                    separator
                        .frame(height: 0.5)
                        .padding(.leading, 62)
                }

                Button(action: {
                    viewModel.selectTypedRecipientCandidate()
                }) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(tint.opacity(0.12))
                                .frame(width: 36, height: 36)

                            Image(systemName: "paperplane.fill")
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(tint)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Use Lightning Address")
                                .font(.body.weight(.medium))
                                .foregroundColor(.black)

                            Text(typedRecipientCandidate)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(separator.opacity(0.75), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 5)
    }

    private func composerSection(for payload: PendingSharedMessagePayload) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if payload.kind == .image || payload.kind == .video {
                SharePayloadVisualPreview(payload: payload)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                separator
                    .frame(height: 0.5)
                    .padding(.top, 12)
            }

            InlineComposerEditor(
                text: $viewModel.composerText,
                placeholder: viewModel.messagePlaceholder,
                minHeight: payload.kind == .text || payload.kind == .url ? 180 : 110,
                isPrefilledShareText: payload.kind == .text || payload.kind == .url
            )
            .focused($focusedField, equals: .message)
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(cardBackground)
        )
    }

    private func errorBanner(message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundColor(Color.red.opacity(0.92))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.red.opacity(0.08))
            )
    }

    private func updateFocus() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if viewModel.selectedRecipient == nil {
                focusedField = .recipient
            } else {
                focusedField = .message
            }
        }
    }
}

private struct SharePayloadVisualPreview: View {
    let payload: PendingSharedMessagePayload

    private var fileURL: URL? {
        ShareMessageExtensionStorage.fileURL(forRelativePath: payload.relativeFilePath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let fileURL {
                if payload.kind == .image {
                    ShareImagePreview(url: fileURL)
                } else {
                    ShareVideoPreview(url: fileURL)
                }
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .frame(height: 220)
                    .overlay {
                        Image(systemName: payload.kind == .image ? "photo.fill" : "video.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
            }

            Text(payload.fileName ?? payload.previewSubtitle)
                .font(.footnote)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .padding(.horizontal, 2)
        }
    }
}

private struct ShareImagePreview: View {
    let url: URL

    var body: some View {
        Group {
            if let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(uiColor: .secondarySystemGroupedBackground)
                    .overlay {
                        Image(systemName: "photo.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct ShareVideoPreview: View {
    let url: URL
    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack {
            Group {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(uiColor: .secondarySystemGroupedBackground)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Image(systemName: "play.circle.fill")
                .font(.system(size: 52, weight: .regular))
                .foregroundColor(.white.opacity(0.94))
                .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
        }
        .task(id: url.path) {
            thumbnail = generateThumbnail(from: url)
        }
    }

    private func generateThumbnail(from url: URL) -> UIImage? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        do {
            let cgImage = try generator.copyCGImage(
                at: CMTime(seconds: 0.1, preferredTimescale: 600),
                actualTime: nil
            )
            return UIImage(cgImage: cgImage)
        } catch {
            return nil
        }
    }
}

private struct RecipientChip: View {
    let recipient: SharedMessageRecipientRecord
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            RecipientAvatar(profilePicURL: recipient.profilePicURL, size: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(recipient.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.black)

                Text(recipient.lightningAddress)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Button(action: onClear) {
                Image(systemName: "xmark.circle.fill")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

private struct RecipientAvatar: View {
    let profilePicURL: String?
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .frame(width: size, height: size)

            if let profilePicURL,
               let url = URL(string: profilePicURL),
               !profilePicURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Image(systemName: "person.fill")
                            .font(.system(size: size * 0.42, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
    }
}

private struct PlaceholderTextEditor: View {
    @Binding var text: String
    let placeholder: String
    let minHeight: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)

            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(placeholder)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
            }

            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(minHeight: minHeight)
                .foregroundColor(.black)
                .background(Color.clear)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled(false)
        }
        .frame(minHeight: minHeight)
    }
}

private struct InlineComposerEditor: View {
    @Binding var text: String
    let placeholder: String
    let minHeight: CGFloat
    let isPrefilledShareText: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isPrefilledShareText {
                Text("Message")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
            }

            ZStack(alignment: .topLeading) {
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(placeholder)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                }

                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(minHeight: minHeight)
                    .foregroundColor(.black)
                    .background(Color.clear)
                    .textInputAutocapitalization(.sentences)
            }
            .frame(minHeight: minHeight)
        }
    }
}
