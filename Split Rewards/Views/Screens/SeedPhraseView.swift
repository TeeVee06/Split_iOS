//
//  SeedPhraseView.swift
//  Split Rewards
//
//

import SwiftUI

struct SeedPhraseBackupView: View {
    /// Seed phrase split into individual words in order.
    let words: [String]

    /// Called when the user confirms they’ve written the phrase down.
    let onConfirm: () -> Void

    /// Optional cancel handler (if presented modally and you want a custom behavior).
    /// If you don’t care, you can pass nil and it will just dismiss.
    let onCancel: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    private let blue = Color.splitBrandBlue
    private let pink = Color.splitBrandPink

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.opacity(0.95)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 24) {

                    // Title
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your Recovery Phrase")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        Text("Write these words down in order and store them somewhere safe. Anyone with this phrase can take your funds. We cannot recover it for you.")
                            .font(.footnote)
                            .foregroundColor(.gray)
                    }

                    // Seed phrase words grid
                    ScrollView {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2),
                            spacing: 8
                        ) {
                            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                                HStack(spacing: 8) {
                                    Text("\(index + 1).")
                                        .font(.footnote)
                                        .foregroundColor(.gray)

                                    Text(word)
                                        .font(.body)
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)

                                    Spacer()
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color.splitInputSurface)
                                .cornerRadius(10)
                            }
                        }
                        .padding(4)
                    }
                    .frame(maxHeight: 260)

                    // Warnings
                    VStack(alignment: .leading, spacing: 6) {
                        Label {
                            Text("Do not share this phrase with anyone.")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .font(.footnote)
                        .foregroundColor(.yellow)

                        Label {
                            Text("Do not store it in screenshots, email, or notes apps.")
                        } icon: {
                            Image(systemName: "lock.fill")
                        }
                        .font(.footnote)
                        .foregroundColor(.gray)
                    }

                    Spacer()

                    // Confirm button
                    Button {
                        onConfirm()
                        dismiss()
                    } label: {
                        Text("I’ve written it down")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [blue, pink]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }

                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if let onCancel {
                            onCancel()
                        }
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
}

// MARK: - Preview

struct SeedPhraseBackupView_Previews: PreviewProvider {
    static var previews: some View {
        SeedPhraseBackupView(
            words: [
                "satoshi", "light", "coffee", "market",
                "rocket", "shadow", "signal", "river",
                "orbit", "tiger", "neon", "window"
            ],
            onConfirm: { },
            onCancel: nil
        )
    }
}
