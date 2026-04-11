//
//  ForceUpdateView.swift
//  Split Rewards
//
//
import SwiftUI

struct ForcedUpdateView: View {
    var body: some View {
        VStack(spacing: 24) {
            Text("Update Required")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Please update to the latest version of Split for continued usage. If you are having any issues please do not hesitate to reach out to support@example.com")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding()

            Button(action: {
                if let url = URL(string: "https://example.com") {
                    UIApplication.shared.open(url)
                }
            }) {
                Text("Update Now")
                    .bold()
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .padding(.horizontal)
        }
        .padding()
    }
}


