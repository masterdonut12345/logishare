//
//  LoginView.swift
//  LogiShare
//
//  Created by Caleb Balboni on 1/1/26.
//


import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var auth: AuthManager

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isWorking = false

    var body: some View {
        VStack(spacing: 14) {
            Text("LogicShare")
                .font(.largeTitle)
                .bold()

            Text("Sign in to access your shared Logic projects.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)

                if let err = auth.authError {
                    Text(err)
                        .foregroundStyle(.red)
                        .font(.callout)
                }

                HStack {
                    Button {
                        // Later: open your website signup page
                        // NSWorkspace.shared.open(URL(string: "https://yourdomain.com/signup")!)
                    } label: {
                        Text("Sign up on website")
                    }
                    .buttonStyle(.link)

                    Spacer()

                    Button {
                        Task {
                            isWorking = true
                            defer { isWorking = false }
                            await auth.login(email: email, password: password)
                        }
                    } label: {
                        if isWorking { ProgressView().controlSize(.small) }
                        Text("Sign In")
                    }
                    .disabled(email.isEmpty || password.isEmpty || isWorking)
                }
            }
            .frame(width: 380)

            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
