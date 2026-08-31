import SwiftUI

struct ReelStudioView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var reelStore: ReelStudioStore
    @EnvironmentObject private var downloadLibrary: DownloadLibraryStore
    @EnvironmentObject private var store: CricketStore
    @State private var goToEditor = false
    @State private var showPicker = false
    @State private var showPreview = false
    @State private var showGuide = false

    private var clips: [ReelClipItem] { reelStore.clips }

    private var totalDuration: String {
        let secs = clips.reduce(0) { partial, item in
            let parts = item.duration.split(separator: ":")
            let s = (Int(parts.first ?? "0") ?? 0) * 60 + (Int(parts.last ?? "0") ?? 0)
            return partial + s
        }
        return String(format: "0:%02d mins", secs)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Selected Highlights")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(.white)
                        Spacer()
                        Text("Use arrows to reorder clips")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.muted)
                    }

                    if clips.isEmpty {
                        Text("No deliveries selected yet")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    } else {
                        ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                            ReelClipRow(
                                clip: clip,
                                canMoveUp: index > 0,
                                canMoveDown: index < clips.count - 1,
                                onMoveUp: {
                                    reelStore.move(from: IndexSet(integer: index), to: index - 1)
                                },
                                onMoveDown: {
                                    reelStore.move(from: IndexSet(integer: index), to: index + 2)
                                }
                            ) {
                                reelStore.remove(id: clip.id)
                            }
                        }
                    }

                    Button { showPicker = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                            Text("Add More Deliveries")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 1, dash: [6]))
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }

            bottomPanel
        }
        .background(Color(red: 0.03, green: 0.035, blue: 0.055).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $goToEditor) {
            VideoEditorView(clips: clips)
                .environmentObject(downloadLibrary)
        }
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                ReelClipPickerView()
                    .environmentObject(reelStore)
                    .environmentObject(store)
            }
        }
        .sheet(isPresented: $showPreview) {
            ReelPreviewSheet(clips: clips)
        }
        .sheet(isPresented: $showGuide) {
            ReelGuideSheet()
        }
        .overlay(alignment: .top) {
            if let toast = reelStore.toastMessage {
                Text(toast)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Theme.accent.opacity(0.95)))
                    .padding(.top, 8)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            reelStore.clearToast()
                        }
                    }
            }
        }
    }

    private var header: some View {
        AppHeader(onLogo: { dismiss() }, showsAvatar: false)
            .padding(.vertical, 4)
            .background(Color(red: 0.07, green: 0.075, blue: 0.10))
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color(white: 0.13)).frame(height: 1)
            }
    }

    private var bottomPanel: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(clips.count) Clips Selected")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(.white)
                    Text("Total Duration: \(totalDuration)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Button {
                    if !clips.isEmpty { showPreview = true }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.circle")
                        Text("Preview Reel")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.06))
                            .overlay(Capsule().stroke(Color(white: 0.13), lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)
            }

            Button {
                if !clips.isEmpty { goToEditor = true }
            } label: {
                Text("Proceed to Video Editor")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(clips.isEmpty ? Theme.muted : Theme.accent))
            }
            .buttonStyle(.plain)
            .disabled(clips.isEmpty)
        }
        .padding(16)
        .background(Color(red: 0.07, green: 0.075, blue: 0.10))
        .overlay(alignment: .top) {
            Rectangle().fill(Color(white: 0.13)).frame(height: 1)
        }
    }
}

struct ReelClipRow: View {
    let clip: ReelClipItem
    var canMoveUp: Bool = false
    var canMoveDown: Bool = false
    var onMoveUp: (() -> Void)? = nil
    var onMoveDown: (() -> Void)? = nil
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 4) {
                Button(action: { onMoveUp?() }) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(canMoveUp ? Theme.accent : Theme.muted)
                }
                .disabled(!canMoveUp)
                Button(action: { onMoveDown?() }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(canMoveDown ? Theme.accent : Theme.muted)
                }
                .disabled(!canMoveDown)
            }
            .buttonStyle(.plain)
            .frame(width: 16)

            ZStack(alignment: .bottomLeading) {
                CoverImage(name: clip.imageName)
                    .frame(width: 80, height: 52)
                    .clipped()
                Text(clip.duration)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 3).fill(.black.opacity(0.7)))
                    .padding(4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(clip.ballLabel)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.white)
                    Text(clip.result)
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(clip.resultIsBoundary ? .black : .white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(clip.resultIsBoundary ? Theme.accent : Theme.liveRed))
                }
                Text(clip.match)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
            }

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.accent.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.07, green: 0.075, blue: 0.10))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(white: 0.13), lineWidth: 1))
        )
    }
}
