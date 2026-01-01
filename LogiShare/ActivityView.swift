//
//  ActivityView.swift
//  LogiShare
//
//  Created by Caleb Balboni on 1/1/26.
//


import SwiftUI

struct ActivityView: View {
    @EnvironmentObject private var store: LocalStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity").font(.title2).bold()

            List(store.activity) { e in
                VStack(alignment: .leading, spacing: 4) {
                    Text(e.title).font(.headline)
                    if let d = e.detail {
                        Text(d).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text(e.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 6)
            }
            .listStyle(.inset)

            Spacer()
        }
        .padding()
    }
}
