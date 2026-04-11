//
//  HowToView.swift
//  Split Rewards
//
//
import SwiftUI

struct HowToViewSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Main Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TitleView(title: "How To Use")
                    
                    Text("Split is intended to be used for in-person purchases at participating restaurants and retail stores. Every dollar you spend via Split earns you more chances to win our monthly reward sweepstakes. There are no payment processing fees for the business when you pay with Split.")
                        .font(.body)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.leading)
                        .padding(.bottom, 30)
                        .padding(.top, 10)
                    
                    Text("**Link Your Bank Account**")
                        .font(.title2)
                        .foregroundColor(.splitBrandBlue)
                        .fontWeight(.heavy)
                    
                    Text("Split uses Stripe to process ACH payments. None of your bank account data ever touches our server. We have implemented industry-leading security and authorization measures to ensure that your Split account remains secure and protected at all times. To be able to make a payment with Split, tap the \"Manage Payments\" button and link your bank account.")
                        .font(.body)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.leading)
                        .padding(.bottom, 30)
                    
                    Text("**Make A Payment**")
                        .font(.title2)
                        .foregroundColor(.splitBrandBlue)
                        .fontWeight(.heavy)
                    
                    Text("To make a payment at one of our participating businesses, just inform the staff you would like to pay with Split. They will present you with a tap-to-pay reader. Hit the \"Tap to Pay\" button and scan the reader.")
                        .font(.body)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.leading)
                        .padding(.bottom, 30)
                    
                    Text("**Rewards**")
                        .font(.title2)
                        .foregroundColor(.splitBrandBlue)
                        .fontWeight(.heavy)
                    
                    Text("To check out our monthly reward sweepstakes and see your current odds of winning, head to the \"Rewards\" tab.")
                        .font(.body)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.leading)
                        .padding(.bottom, 30)
                }
                .padding(.horizontal)
            }
           
        }
        .padding(.top)
    }
}
