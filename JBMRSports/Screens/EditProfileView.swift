import PhotosUI
import SwiftUI
import UIKit

struct EditProfileView: View {
    @ObservedObject private var authStore = AuthStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var saving = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        ProfileAvatarView(size: 108)
                        Image(systemName: "camera.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Theme.accent))
                            .overlay(Circle().stroke(Theme.background, lineWidth: 2))
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 24)

                Text("Photo change karne ke liye icon dabao")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Name")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                    TextField("Apna naam", text: $name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                }
                .padding(.horizontal, 16)

                Text(authStore.phoneLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)

                Button {
                    Task {
                        saving = true
                        let ok = await authStore.updateDisplayName(name)
                        saving = false
                        if ok { dismiss() }
                    }
                } label: {
                    Group {
                        if saving {
                            ProgressView().tint(.white)
                        } else {
                            Text("Save profile")
                                .font(.system(size: 16, weight: .bold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.accent))
                }
                .buttonStyle(.plain)
                .disabled(saving)
                .padding(.horizontal, 16)

                if authStore.avatarData != nil {
                    Button("Photo hatao") {
                        authStore.clearAvatar()
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.liveRed)
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { name = authStore.displayName }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data),
                   let jpeg = image.jpegData(compressionQuality: 0.82) {
                    authStore.setAvatarJPEG(jpeg)
                }
            }
        }
        .alert("Profile", isPresented: Binding(
            get: { authStore.errorMessage != nil },
            set: { if !$0 { authStore.clearError() } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(authStore.errorMessage ?? "")
        }
    }
}
