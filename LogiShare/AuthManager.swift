//
//  AuthManager.swift
//  LogiShare
//
//  Created by Caleb Balboni on 1/1/26.
//


import Foundation

@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var tokens: AuthTokens? = nil
    @Published private(set) var me: UserProfile? = nil
    @Published var authError: String? = nil

    private let api: AuthAPI

    private let keychainService = "LogicShare.Auth"
    private let keychainAccount = "tokens"

    init(api: AuthAPI = MockAuthAPI()) {
        self.api = api
        loadFromKeychain()
    }

    var isLoggedIn: Bool { tokens != nil }

    func login(email: String, password: String) async {
        authError = nil
        do {
            let t = try await api.login(email: email, password: password)
            tokens = t
            try saveToKeychain(t)
            await loadMe()
        } catch {
            authError = error.localizedDescription
        }
    }

    func logout() {
        tokens = nil
        me = nil
        authError = nil
        try? KeychainHelper.delete(service: keychainService, account: keychainAccount)
    }

    func loadMe() async {
        guard let t = tokens else { return }
        do {
            // refresh if expired (simple check; later add leeway)
            if t.expiresAt <= Date() {
                let newTokens = try await api.refresh(refreshToken: t.refreshToken)
                tokens = newTokens
                try saveToKeychain(newTokens)
            }

            guard let access = tokens?.accessToken else { return }
            me = try await api.me(accessToken: access)
        } catch {
            authError = error.localizedDescription
        }
    }

    // MARK: - Keychain

    private func saveToKeychain(_ t: AuthTokens) throws {
        let data = try JSONEncoder.withISO8601.encode(t)
        try KeychainHelper.set(data, service: keychainService, account: keychainAccount)
    }

    private func loadFromKeychain() {
        do {
            guard let data = try KeychainHelper.get(service: keychainService, account: keychainAccount) else { return }
            let decoded = try JSONDecoder.withISO8601.decode(AuthTokens.self, from: data)
            tokens = decoded
            Task { await loadMe() }
        } catch {
            authError = error.localizedDescription
        }
    }
}
