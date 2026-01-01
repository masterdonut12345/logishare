//
//  AuthTokens.swift
//  LogiShare
//
//  Created by Caleb Balboni on 1/1/26.
//


import Foundation

struct AuthTokens: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
}

struct UserProfile: Codable, Equatable {
    let id: String
    let email: String
    let displayName: String?
    let subscriptionActive: Bool
}
