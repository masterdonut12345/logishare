//
//  AuthAPI.swift
//  LogiShare
//
//  Created by Caleb Balboni on 1/1/26.
//


import Foundation

protocol AuthAPI {
    func login(email: String, password: String) async throws -> AuthTokens
    func me(accessToken: String) async throws -> UserProfile
    func refresh(refreshToken: String) async throws -> AuthTokens
}

/// Use this during development before the server exists.
/// Replace with ServerAuthAPI later.
final class MockAuthAPI: AuthAPI {
    func login(email: String, password: String) async throws -> AuthTokens {
        try await Task.sleep(nanoseconds: 450_000_000)
        if email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty {
            throw NSError(domain: "MockAuth", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "Email/password required."
            ])
        }
        return AuthTokens(
            accessToken: "mock_access_\(UUID().uuidString)",
            refreshToken: "mock_refresh_\(UUID().uuidString)",
            expiresAt: Date().addingTimeInterval(60 * 60)
        )
    }

    func me(accessToken: String) async throws -> UserProfile {
        try await Task.sleep(nanoseconds: 200_000_000)
        return UserProfile(
            id: "mock_user",
            email: "user@example.com",
            displayName: "Caleb",
            subscriptionActive: true
        )
    }

    func refresh(refreshToken: String) async throws -> AuthTokens {
        try await Task.sleep(nanoseconds: 250_000_000)
        return AuthTokens(
            accessToken: "mock_access_\(UUID().uuidString)",
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(60 * 60)
        )
    }
}
