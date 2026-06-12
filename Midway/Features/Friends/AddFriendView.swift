import SwiftUI
import CoreImage.CIFilterBuiltins

struct AddFriendView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("By Midway username") {
                    HStack {
                        TextField("username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Send") {
                            appState.addFriend(username: username)
                            username = ""
                            dismiss()
                        }
                        .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                if let inviteURL = appState.inviteURL {
                    Section("Invite link") {
                        ShareLink(item: inviteURL) {
                            Label("Share your invite link", systemImage: "square.and.arrow.up")
                        }
                    }

                    Section("Your QR code") {
                        HStack {
                            Spacer()
                            QRCodeView(string: inviteURL.absoluteString)
                                .frame(width: 180, height: 180)
                            Spacer()
                        }
                        Text("Friends can scan this with their camera to add you on Midway.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Add friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct QRCodeView: View {
    let string: String

    var body: some View {
        if let image = Self.qrImage(for: string) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "qrcode")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
        }
    }

    private static func qrImage(for string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

#Preview {
    AddFriendView().environmentObject(AppState())
}
