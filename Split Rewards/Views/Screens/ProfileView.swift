//  ProfileView.swift
//  Split Rewards
//
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

private let splitBlue = Color.splitBrandBlue
private let splitPink = Color.splitBrandPink

private func alternatingProfileColor(at index: Int) -> Color {
    index.isMultiple(of: 2) ? splitBlue : splitPink
}

struct ProfileView: View {
    @EnvironmentObject var walletManager: WalletManager
    @EnvironmentObject var authManager: AuthManager

    private let background = Color.splitSoftBackground
    private let cardSurface = Color.splitInputSurfaceTertiary
    private let cardStroke = Color.white.opacity(0.06)

    @State private var lightningAddress: WalletManager.LightningAddressInfo?
    @State private var messagingRegistration: MessageKeyManager.RegistrationResponse?
    @State private var profilePicUrl: String?
    @State private var selectedProfileImage: UIImage?
    @State private var pickedPhotoImage: UIImage?
    @State private var isLoadingAddress = true
    @State private var isUploadingProfilePic = false
    @State private var addressLoadError: String?
    @State private var profilePicUploadError: String?

    @State private var showingCreateSheet = false
    @State private var showingQRSheet = false
    @State private var showingPhotoSourceDialog = false
    @State private var showingImagePicker = false
    @State private var showingFileImporter = false

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                profileHeaderSection

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {

                        navCard(
                            image: "arrow.down.circle.fill",
                            iconColor: alternatingProfileColor(at: 0),
                            title: "Claim Your Bitcoin",
                            subtitle: "Claim when ready.",
                            destination: BitcoinPending()
                        )
                        .padding(.top, 14)
                        
                        navCard(
                            image: "circle.rectangle.filled.pattern.diagonalline",
                            iconColor: alternatingProfileColor(at: 1),
                            title: "Proof Of Spend",
                            subtitle: "Manage your posts.",
                            destination: ManagePOSPostsView()
                        )

                        navCard(
                            image: "storefront.fill",
                            iconColor: alternatingProfileColor(at: 2),
                            title: "Add a Merchant",
                            subtitle: "Help us add any BTC business.",
                            destination: AddMerchantView()
                        )

                        navCard(
                            image: "atom",
                            iconColor: alternatingProfileColor(at: 3),
                            title: "Rewards Explained",
                            subtitle: "How it works.",
                            destination: RewardsInfo()
                        )

                        navCard(
                            image: "questionmark.bubble.fill",
                            iconColor: alternatingProfileColor(at: 4),
                            title: "Contact / Support",
                            subtitle: "Questions, feedback, and product ideas.",
                            destination: SupportView()
                        )

                        navCard(
                            image: "flag.slash.fill",
                            iconColor: alternatingProfileColor(at: 5),
                            title: "Content Moderation",
                            subtitle: "Blocking and reporting content/users.",
                            destination: ContentModerationView()
                        )

                        navCard(
                            image: "doc.text.fill",
                            iconColor: alternatingProfileColor(at: 6),
                            title: "Legal",
                            subtitle: "Documents and agreements.",
                            destination: LegalView()
                        )

                        navCard(
                            image: "key.fill",
                            iconColor: alternatingProfileColor(at: 7),
                            title: "Wallet Management",
                            subtitle: "Wallet device access.",
                            destination: WalletManagementView()
                        )

                        Spacer(minLength: 28)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task {
                await loadProfileContent()
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            CreateLightningAddressSheet { createdAddress, registration in
                lightningAddress = createdAddress
                messagingRegistration = registration
            }
            .environmentObject(walletManager)
            .environmentObject(authManager)
        }
        .sheet(isPresented: $showingQRSheet) {
            if let lightningAddress {
                IdentityShareSheet(
                    lightningAddress: lightningAddress.lightningAddress,
                    suggestedContactName: suggestedContactName(for: lightningAddress),
                    paymentQRString: qrPayload(for: lightningAddress),
                    contactQRString: contactPayload(for: lightningAddress)
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
            }
        }
        .confirmationDialog(
            "Update Profile Photo",
            isPresented: $showingPhotoSourceDialog,
            titleVisibility: .visible
        ) {
            Button("Choose Photo") {
                showingImagePicker = true
            }

            Button("Choose File") {
                showingFileImporter = true
            }

            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Choose an image from your photo library or Files.")
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(image: $pickedPhotoImage)
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            handleProfileFileSelection(result)
        }
        .onChange(of: pickedPhotoImage) { _, newImage in
            guard let newImage else { return }

            Task {
                await handleSelectedPhoto(newImage)
            }
        }
    }

    private var profileHeaderSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                profilePhotoSection

                VStack(alignment: .leading, spacing: 8) {
                    Text("Profile")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)

                    Text("Lightning identity and app settings")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.58))
                }

                Spacer(minLength: 0)
            }

            if let profilePicUploadError {
                Text(profilePicUploadError)
                    .font(.subheadline)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.leading)
            }

            lightningAddressSection
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 22)
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0.96),
                    Color.splitInputSurface.opacity(0.98)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(splitPink.opacity(0.12))
                    .frame(width: 180, height: 180)
                    .blur(radius: 28)
                    .offset(x: 64, y: -72)
            }
            .overlay(alignment: .bottomLeading) {
                Circle()
                    .fill(splitBlue.opacity(0.10))
                    .frame(width: 220, height: 220)
                    .blur(radius: 34)
                    .offset(x: -96, y: 58)
            }
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var lightningAddressSection: some View {
        if isLoadingAddress {
            HStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))

                Text("Loading Lightning Address...")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.72))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.white.opacity(0.05))
            )

        } else if let addressLoadError {
            VStack(alignment: .leading, spacing: 10) {
                Text(addressLoadError)
                    .font(.subheadline)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.leading)

                Button(action: {
                    Task { await loadLightningAddress() }
                }) {
                    Text("Retry")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(splitBlue)
                        )
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.white.opacity(0.05))
            )

        } else if let lightningAddress {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Lightning Address")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.56))

                    Text(lightningAddress.lightningAddress)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                Button(action: {
                    showingQRSheet = true
                }) {
                    Image(systemName: "qrcode")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(width: 48, height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(splitBlue)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )

        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Setup a Lightning Address for this wallet.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.68))
                    .multilineTextAlignment(.leading)

                Button(action: {
                    showingCreateSheet = true
                }) {
                    Text("Create Lightning Address")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(splitBlue)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
    }

    private var profilePhotoSection: some View {
        Button {
            showingPhotoSourceDialog = true
        } label: {
            Group {
                if let selectedProfileImage {
                    Image(uiImage: selectedProfileImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 92, height: 92)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                } else if let profilePicURL = URL(string: profilePicUrl ?? ""),
                          let profilePicUrl,
                          !profilePicUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    AsyncImage(url: profilePicURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .empty:
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        case .failure:
                            profilePhotoPlaceholder
                        @unknown default:
                            profilePhotoPlaceholder
                        }
                    }
                    .frame(width: 92, height: 92)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                } else {
                    profilePhotoPlaceholder
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isUploadingProfilePic)
    }

    @ViewBuilder
    private func navCard<Destination: View>(
        image: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        destination: Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white)

                    Image(systemName: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .foregroundColor(iconColor)
                }
                .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.60))
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.78))
            }
            .padding(16)
            .background(cardSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(cardStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }

    private var profilePhotoPlaceholder: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.08))

            Text("+ add photo")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
        }
        .frame(width: 92, height: 92)
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func loadProfileContent() async {
        await loadProfilePic()
        await loadLightningAddress()
    }

    private func loadProfilePic() async {
        do {
            let response = try await ProfilePicAPI.fetchProfilePic(
                authManager: authManager,
                walletManager: walletManager
            )
            profilePicUrl = response.profilePicUrl
        } catch {
            print("Failed to load profile picture: \(error.localizedDescription)")
            profilePicUrl = nil
        }
    }

    private func handleSelectedPhoto(_ image: UIImage) async {
        guard let fileData = image.jpegData(compressionQuality: 0.9) else {
            profilePicUploadError = "Failed to prepare selected photo."
            pickedPhotoImage = nil
            return
        }

        await uploadProfilePic(
            fileData: fileData,
            fileName: "profile-photo.jpg",
            mimeType: "image/jpeg",
            previewImage: image
        )

        pickedPhotoImage = nil
    }

    private func handleProfileFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let data = try Data(contentsOf: url)
                guard let image = UIImage(data: data) else {
                    profilePicUploadError = "Selected file could not be used as a profile picture."
                    return
                }

                let fileName = url.lastPathComponent.isEmpty ? "profile-file" : url.lastPathComponent
                let mimeType = mimeTypeForProfileFile(at: url)

                Task {
                    await uploadProfilePic(
                        fileData: data,
                        fileName: fileName,
                        mimeType: mimeType,
                        previewImage: image
                    )
                }
            } catch {
                profilePicUploadError = "Failed to read selected file."
                print("Failed to read selected profile file: \(error.localizedDescription)")
            }
        case .failure(let error):
            print("Profile file import cancelled or failed: \(error.localizedDescription)")
        }
    }

    private func uploadProfilePic(
        fileData: Data,
        fileName: String,
        mimeType: String,
        previewImage: UIImage
    ) async {
        isUploadingProfilePic = true
        profilePicUploadError = nil

        do {
            let response = try await ProfilePicUploadAPI.postProfilePic(
                fileData: fileData,
                fileName: fileName,
                mimeType: mimeType,
                authManager: authManager,
                walletManager: walletManager
            )

            selectedProfileImage = previewImage
            profilePicUrl = response.profilePicUrl ?? profilePicUrl
        } catch {
            profilePicUploadError = error.localizedDescription
            print("Failed to upload profile picture: \(error.localizedDescription)")
        }

        isUploadingProfilePic = false
    }

    private func mimeTypeForProfileFile(at url: URL) -> String {
        if let values = try? url.resourceValues(forKeys: [.contentTypeKey]),
           let contentType = values.contentType,
           let mimeType = contentType.preferredMIMEType {
            return mimeType
        }

        return "application/octet-stream"
    }

    private func loadLightningAddress() async {
        isLoadingAddress = true
        addressLoadError = nil

        do {
            let fetched = try await walletManager.fetchLightningAddress()
            lightningAddress = fetched

            if fetched != nil {
                do {
                    messagingRegistration = try await MessageKeyManager.shared.ensureRegistered(
                        authManager: authManager,
                        walletManager: walletManager
                    )
                } catch {
                    messagingRegistration = nil
                    print("Failed to sync messaging identity: \(error.localizedDescription)")
                }
            } else {
                messagingRegistration = nil
            }
        } catch {
            addressLoadError = error.localizedDescription
            lightningAddress = nil
            messagingRegistration = nil
        }

        isLoadingAddress = false
    }

    private func qrPayload(for info: WalletManager.LightningAddressInfo) -> String {
        if !info.lnurlBech32.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return info.lnurlBech32
        }

        return "lightning:\(info.lightningAddress)"
    }

    private func suggestedContactName(for info: WalletManager.LightningAddressInfo) -> String {
        let address = info.lightningAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let username = address.split(separator: "@").first, !username.isEmpty else {
            return "Split User"
        }

        return String(username)
    }

    private func contactPayload(for info: WalletManager.LightningAddressInfo) -> String {
        struct SplitContactPayload: Encodable {
            let type: String
            let version: Int
            let lightningAddress: String
            let suggestedName: String
            let profilePicUrl: String?
            let walletPubkey: String?
            let messagingPubkey: String?
            let messagingIdentitySignature: String?
            let messagingIdentitySignatureVersion: Int?
            let messagingIdentitySignedAt: Int?
        }

        let normalizedLightningAddress = info.lightningAddress
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let signedBinding = messagingRegistration?.identityBindingPayload
        let shouldEmbedSignedBinding = signedBinding?.lightningAddress == normalizedLightningAddress

        let payload = SplitContactPayload(
            type: "split_contact",
            version: 1,
            lightningAddress: normalizedLightningAddress,
            suggestedName: suggestedContactName(for: info),
            profilePicUrl: profilePicUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? profilePicUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil,
            walletPubkey: shouldEmbedSignedBinding ? signedBinding?.walletPubkey : nil,
            messagingPubkey: shouldEmbedSignedBinding ? signedBinding?.messagingPubkey : nil,
            messagingIdentitySignature: shouldEmbedSignedBinding ? signedBinding?.messagingIdentitySignature : nil,
            messagingIdentitySignatureVersion: shouldEmbedSignedBinding ? signedBinding?.messagingIdentitySignatureVersion : nil,
            messagingIdentitySignedAt: shouldEmbedSignedBinding ? signedBinding?.messagingIdentitySignedAt : nil
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        guard let data = try? encoder.encode(payload),
              let jsonString = String(data: data, encoding: .utf8) else {
            return "split-contact:{\"lightningAddress\":\"\(info.lightningAddress.lowercased())\",\"suggestedName\":\"\(suggestedContactName(for: info))\",\"type\":\"split_contact\",\"version\":1}"
        }

        return "split-contact:\(jsonString)"
    }
}

private struct CreateLightningAddressSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var walletManager: WalletManager
    @EnvironmentObject private var authManager: AuthManager

    let onCreated: (WalletManager.LightningAddressInfo, MessageKeyManager.RegistrationResponse?) -> Void

    @State private var username = ""
    @State private var checkedUsername: String?
    @State private var isUsernameAvailable = false

    @State private var isCheckingAvailability = false
    @State private var isCreatingAddress = false
    @State private var errorMessage: String?

    private var normalizedUsernamePreview: String {
        username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private var canCheckAvailability: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !isCheckingAvailability
        && !isCreatingAddress
    }

    private var canCreateAddress: Bool {
        checkedUsername == normalizedUsernamePreview
        && isUsernameAvailable
        && !isCreatingAddress
        && !isCheckingAvailability
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 20) {

                    Text("Choose a username")
                        .font(.title2.bold())
                        .foregroundColor(.white)

                    Text("This will become your Lightning Address.")
                        .font(.subheadline)
                        .foregroundColor(.gray)

                    VStack(alignment: .leading, spacing: 10) {

                        Text("Username")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)

                        HStack(spacing: 8) {
                            TextField("username", text: $username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.asciiCapable)
                                .foregroundColor(.white)

                            Text("@\(AppConfig.lightningAddressDomain)")
                                .foregroundColor(.gray.opacity(0.5))
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.08))
                        )
                        .onChange(of: username) { _, _ in
                            errorMessage = nil
                            checkedUsername = nil
                            isUsernameAvailable = false
                        }

                        Text("Allowed: letters, numbers, periods, underscores, and hyphens.")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }

                    if !normalizedUsernamePreview.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Preview")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)

                            Text(normalizedUsernamePreview)
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                    }

                    if let checkedUsername, isUsernameAvailable {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Available")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(splitPink)

                            Text("Your address will be created with username: \(checkedUsername)")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundColor(.red)
                    }

                    Spacer()

                    VStack(spacing: 12) {

                        Button(action: {
                            Task { await checkAvailability() }
                        }) {
                            HStack {
                                if isCheckingAvailability {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                } else {
                                    Text("Check Availability")
                                        .font(.headline)
                                }
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(canCheckAvailability ? splitBlue : Color.gray.opacity(0.4))
                            )
                        }
                        .disabled(!canCheckAvailability)

                        Button(action: {
                            Task { await createLightningAddress() }
                        }) {
                            HStack {
                                if isCreatingAddress {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                } else {
                                    Text("Create Lightning Address")
                                        .font(.headline)
                                }
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(canCreateAddress ? splitPink : Color.gray.opacity(0.4))
                            )
                        }
                        .disabled(!canCreateAddress)
                    }
                }
                .padding(24)
            }
            .navigationTitle("Create Address")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .disabled(isCheckingAvailability || isCreatingAddress)
                }
            }
        }
    }

    private func checkAvailability() async {
        errorMessage = nil

        do {
            let normalized = try walletManager.normalizedLightningUsername(username)

            isCheckingAvailability = true
            let available = try await walletManager.isLightningAddressAvailable(username: normalized)
            isCheckingAvailability = false

            checkedUsername = normalized
            isUsernameAvailable = available

            if !available {
                errorMessage = WalletManager.LightningAddressError.usernameUnavailable.localizedDescription
            }

        } catch {
            isCheckingAvailability = false
            checkedUsername = nil
            isUsernameAvailable = false
            errorMessage = error.localizedDescription
        }
    }

    private func createLightningAddress() async {
        errorMessage = nil
        isCreatingAddress = true

        do {
            let created = try await walletManager.createLightningAddress(username: username)
            var registration: MessageKeyManager.RegistrationResponse?

            do {
                registration = try await MessageKeyManager.shared.ensureRegistered(
                    authManager: authManager,
                    walletManager: walletManager
                )
            } catch {
                print("Failed to sync newly created messaging identity: \(error.localizedDescription)")
            }

            isCreatingAddress = false
            onCreated(created, registration)
            dismiss()
        } catch {
            isCreatingAddress = false
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        ProfileView()
            .environmentObject(WalletManager())
            .environmentObject(AuthManager())
    }
}
