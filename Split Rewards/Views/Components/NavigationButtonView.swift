//
//  NavigationButtonView.swift
//  Split-iOS
//
//
import SwiftUI

struct NavigationButtonView<Destination: View>: View {
    let title: String
    let destination: Destination

    var body: some View {
        NavigationLink(destination: destination) {
            Text(title)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.splitBrandBlue)
                .cornerRadius(12)
                .foregroundColor(.white)
        }
    }
}
