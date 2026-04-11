import SwiftUI

struct ContentModerationView: View {
    private let background = Color.black
    private let surface = Color.splitInputSurface
    private let accentBlue = Color.splitBrandBlue
    private let accentPink = Color.splitBrandPink

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    heroCard

                    infoCard(
                        title: "Blocking Users",
                        icon: "nosign",
                        iconColor: accentPink,
                        lines: [
                            "To block someone, open that person's detail view and tap the block icon.",
                            "Once blocked, you will not receive messages from that user and their Proof of Spend posts will no longer appear in your feed.",
                            "Blocking another user is at the complete discretion of each user."
                        ]
                    )

                    infoCard(
                        title: "Reporting Posts",
                        icon: "flag.fill",
                        iconColor: accentBlue,
                        lines: [
                            "To report a Proof of Spend post, tap the flag button on the lower-left side of the post and confirm the report.",
                            "Reporting a post should be reserved for highly offensive or illegal content.",
                            "If you simply do not want to interact with someone, blocking that user is usually the better tool."
                        ]
                    )
                }
                .padding(.horizontal, 18)
                .padding(.top, 20)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("Content Moderation")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var heroCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            accentBlue,
                            accentPink
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 12) {
                Text("Blocking and Reporting")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)

                Text("Use blocking for your own comfort and safety. Use reporting when content crosses a serious line and needs review.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
        }
        .frame(minHeight: 194)
    }

    private func infoCard(
        title: String,
        icon: String,
        iconColor: Color,
        lines: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white)
                        .frame(width: 46, height: 46)

                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(iconColor)
                }

                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(lines, id: \.self) { line in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(Color.white.opacity(0.78))
                            .frame(width: 6, height: 6)
                            .padding(.top, 7)

                        Text(line)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.76))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
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
}

#Preview {
    NavigationStack {
        ContentModerationView()
    }
}
