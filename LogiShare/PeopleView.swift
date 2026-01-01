//
//  PeopleView.swift
//  LogiShare
//
//  Created by Caleb Balboni on 1/1/26.
//


import SwiftUI

struct PeopleView: View {
    // Local placeholder until server exists
    @State private var members: [Person] = [
        .init(id: UUID(), name: "You", role: "Owner"),
        .init(id: UUID(), name: "Teammate (example)", role: "Editor")
    ]
    @State private var inviteName: String = ""
    @State private var inviteRole: String = "Viewer"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("People").font(.title2).bold()
            Text("This will become real invites/permissions once the server is set up.")
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                TextField("Invite name or email (placeholder)", text: $inviteName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)

                Picker("Role", selection: $inviteRole) {
                    Text("Viewer").tag("Viewer")
                    Text("Editor").tag("Editor")
                }
                .frame(width: 140)

                Button("Add") {
                    let trimmed = inviteName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    members.append(Person(id: UUID(), name: trimmed, role: inviteRole))
                    inviteName = ""
                }
            }

            List {
                ForEach(members) { m in
                    HStack {
                        Image(systemName: "person.circle")
                        Text(m.name)
                        Spacer()
                        Text(m.role).foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.inset)

            Spacer()
        }
        .padding()
    }
}
