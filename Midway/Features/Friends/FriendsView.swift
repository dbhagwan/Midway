import SwiftUI

/// Friends, Snapchat-style: big avatars, bold names, glass cards.
struct FriendsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showAddFriend = false

    private var outgoing: [Friend] {
        appState.friends.filter { $0.status == .outgoingRequest }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                GlassEffectContainer(spacing: 14) {
                    VStack(spacing: 14) {
                        if !appState.incomingRequests.isEmpty {
                            SectionLabel(text: "Added me")
                            ForEach(appState.incomingRequests) { friend in
                                requestCard(friend)
                            }
                        }

                        SectionLabel(text: "My friends")
                        if appState.acceptedFriends.isEmpty {
                            emptyCard
                        } else {
                            ForEach(appState.acceptedFriends) { friend in
                                friendCard(friend)
                            }
                        }

                        if !outgoing.isEmpty {
                            SectionLabel(text: "Pending")
                            ForEach(outgoing) { friend in
                                pendingCard(friend)
                            }
                        }
                    }
                    .padding()
                }
            }
            .background(MidwayBackground())
            .navigationTitle("Friends")
            .toolbar {
                Button {
                    showAddFriend = true
                } label: {
                    Image(systemName: "person.badge.plus")
                }
            }
            .sheet(isPresented: $showAddFriend) {
                AddFriendView()
            }
            .refreshable {
                await appState.refresh()
            }
        }
    }

    // MARK: - Cards

    private func friendCard(_ friend: Friend) -> some View {
        HStack(spacing: 14) {
            AvatarView(name: friend.displayName, url: friend.avatarURL, size: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(friend.displayName)
                    .font(.headline)
                Text(subtitle(for: friend))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !friend.interests.isEmpty {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.midwayAmber)
            }
        }
        .glassCard()
        .contextMenu {
            Button(role: .destructive) {
                appState.block(friend, report: false)
            } label: {
                Label("Block \(friend.displayName)", systemImage: "hand.raised")
            }
            Button(role: .destructive) {
                appState.block(friend, report: true)
            } label: {
                Label("Block & report", systemImage: "exclamationmark.bubble")
            }
        }

    private func requestCard(_ friend: Friend) -> some View {
        HStack(spacing: 14) {
            AvatarView(name: friend.displayName, url: friend.avatarURL, size: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(friend.displayName).font(.headline)
                Text("wants to be friends")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                appState.respondToFriendRequest(friend, accept: true)
            } label: {
                Image(systemName: "checkmark")
                    .fontWeight(.bold)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.glassProminent)
            .tint(.midwayTeal)
            Button {
                appState.respondToFriendRequest(friend, accept: false)
            } label: {
                Image(systemName: "xmark")
                    .fontWeight(.bold)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.glass)
        }
        .glassCard()
    }

    private func pendingCard(_ friend: Friend) -> some View {
        HStack(spacing: 14) {
            AvatarView(name: friend.displayName, url: friend.avatarURL, size: 44)
            Text(friend.displayName).font(.headline)
            Spacer()
            Text("Invited")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .glassCard()
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            AvatarStack(names: ["Ava", "Leo", "Maya"], size: 40)
            Text("No friends on Midway yet")
                .font(.headline)
            Text("Invite friends with your link or QR code — Midway shows only friends who are here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add friends") { showAddFriend = true }
                .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity)
        .glassCard(padding: 24)
    }

    private func subtitle(for friend: Friend) -> String {
        var parts = ["@\(friend.username)"]
        if !friend.homeAreaName.isEmpty {
            parts.append(friend.homeAreaName)
        }
        return parts.joined(separator: " · ")
    }
}

#Preview {
    FriendsView().environmentObject(AppState())
}
