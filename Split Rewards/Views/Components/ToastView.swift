//
//  ToastView.swift
//  Split Rewards
//
//  A global toast/banner overlay that listens to ToastManager
//  and shows a single toast at the top of the screen.
//

import SwiftUI

struct ToastView: View {
    @EnvironmentObject var toastManager: ToastManager
    
    let blue = Color.splitBrandBlue
    let pink = Color.splitBrandPink
    let white = Color.white

    var body: some View {
        ZStack(alignment: .top) {
            if let toast = toastManager.activeToast {
                toastBanner(for: toast)
                    .transition(
                        .move(edge: .top)
                        .combined(with: .opacity)
                    )
                    .zIndex(1)
            }
        }
        // Animate changes in the active toast.
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: toastManager.activeToast)
    }

    // MARK: - Banner content

    @ViewBuilder
    private func toastBanner(for toast: AppToast) -> some View {
        VStack {
            // Respect the safe area at the top.
            Spacer()
                .frame(height: UIApplication.shared.topSafeAreaInset)

            HStack(spacing: 14) {
                Image(systemName: iconName(for: toast))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(iconColor(for: toast))

                VStack(alignment: .leading, spacing: 4) {
                    Text(toast.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)

                    if let subtitle = toast.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(3)
                    }
                }

                Spacer()

                Button(action: {
                    toastManager.hide()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(8)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            // Bigger toast: more padding + minimum height
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(minHeight: 96, alignment: .center)
            .background(
                blurBackground(for: toast)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 18) // extra bottom padding to bring it further down

            Spacer() // Push banner to top
        }
    }

    // MARK: - Icon + colors

    private func iconName(for toast: AppToast) -> String {
        switch toast.kind {
        case .paymentPending:
            return "clock"
        case .paymentSuccess:
            // Same color for all successes; icon changes by direction.
            switch toast.direction {
            case .sent:
                return "arrow.up.right.circle.fill"
            case .received:
                return "arrow.down.left.circle.fill"
            case .none:
                return "checkmark.circle.fill"
            }
        case .paymentFailure:
            return "exclamationmark.triangle.fill"
        case .info:
            return "info.circle.fill"
        case .error:
            return "exclamationmark.octagon.fill"
        }
    }

    private func iconColor(for toast: AppToast) -> Color {
        switch toast.kind {
        case .paymentPending:
            return Color.yellow
        case .paymentSuccess:
            // Same success color regardless of direction.
            return blue
        case .paymentFailure:
            return Color.red
        case .info:
            return Color.white
        case .error:
            return Color.red
        }
    }

    private func blurBackground(for toast: AppToast) -> some View {
        // Same base tint for all success toasts, regardless of direction.
        let tint: Color
        switch toast.kind {
        case .paymentPending:
            tint = Color.yellow.opacity(0.25)
        case .paymentSuccess:
            tint = blue.opacity(0.30)
        case .paymentFailure:
            tint = Color.red.opacity(0.35)
        case .info:
            tint = Color.gray.opacity(0.30)
        case .error:
            tint = Color.red.opacity(0.35)
        }

        return ZStack {
            // A subtle blur-like background.
            tint
                .background(.ultraThinMaterial)
        }
    }
}

// MARK: - Safe area helper

private extension UIApplication {
    var topSafeAreaInset: CGFloat {
        let keyWindow = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }

        return keyWindow?.safeAreaInsets.top ?? 0
    }
}

// MARK: - Preview

struct ToastView_Previews: PreviewProvider {
    static var previews: some View {
        let manager = ToastManager()
        manager.showPaymentPending() // Defaults to .sent, backwards-compatible

        return ZStack {
            Color.black.ignoresSafeArea()
            ToastView()
                .environmentObject(manager)
        }
    }
}



