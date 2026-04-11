//
//  ActionButtonView.swift
//  Split
//
//
import SwiftUI

struct ActionButtonView: View {
    let title: String
    let color: Color // Make sure the color is of type Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity)
                .padding()
                .background(color) // Use the color here
                .cornerRadius(12)
                .foregroundColor(.white)
        }
    }
}



