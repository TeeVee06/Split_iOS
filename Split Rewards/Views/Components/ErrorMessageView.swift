//
//  ErrorMessageView.swift
//  Split
//
//
import SwiftUI

struct ErrorMessageView: View {
    var message: String
    
    var body: some View {
        Text(message)
            .foregroundColor(.red)
            .font(.footnote)
            .padding()
    }
}

struct ErrorMessageView_Previews: PreviewProvider {
    static var previews: some View {
        ErrorMessageView(message: "Invalid credentials.")
    }
}

