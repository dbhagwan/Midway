import SwiftUI

struct FriendsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showAddFriend = false

    var body: some View {
        NavigationStack {
            List {
                if !appState.incomingRequests.isEmpty {
                    Section("Requests") {
                        ForEach(appState.incomingRequests) { friend in
                            FriendRow(friend: friend) {
                                HStack(spacing: 12) {
                                    Button {
                                        appState.respondToFriendRequest(friend, accept: true)
                                    } label: {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                    Button {
                                        appState.respondToFriendRequest(friend, accept: false)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.red)
                                    }
                                }
                                .font(.title2)
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Section("Friends on Midway") {
                    if appState.acceptedFriends.isEmpty {
                        ContentUnavailableView(
                            "No friends yet",
                            systemImage: "person.2",
                            description: Text("Invite friends to Midway to start planning meetups.")
                        )
                    } else {
                        ForEach(appState.acceptedFriends) { friend in
                            FriendRow(friend: friend) {
                                Text(friend.homeAreaName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                let outgoing = appState.friends.filter { $0.status == .outgoingRequest }
                if !outgoing.isEmpty {
                    Section("Sent") {
                        ForEach(outgoing) { friend in
                            FriendRow(friend: friend) {
                                Text("Pending")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
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
        }
    }
}

struct FriendRow<Trailing: View>: View {
    let friend: Friend
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            AvatarView(name: friend.displayName, url: friend.avatarURL)
            VStack(alignment: .leading) {
                Text(friend.displayName)
                Text("@\(friend.username)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
    }
}

/// Bitmoji avatar when available, monogram circle otherwise.
struct AvatarView: View {
    let name: String
    var url: URL?
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    monogram
                }
            } else {
                monogram
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var monogram: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.2))
            .overlay {
                Text(String(name.prefix(1)))
                    .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
            }
    }
}

#Preview {
    FriendsView().environmentObject(AppState())
}
