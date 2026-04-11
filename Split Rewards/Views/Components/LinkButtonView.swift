//
//  LinkButtonView.swift
//  Split
//
//
import SwiftUI

struct LinkButtonView: View {
    var title: String
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.footnote)
                .foregroundColor(.blue)
        }
    }
}

struct LinkButtonView_Previews: PreviewProvider {
    static var previews: some View {
        LinkButtonView(title: "Forgot Password?", action: {})
    }
}

