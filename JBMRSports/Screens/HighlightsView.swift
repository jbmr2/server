import SwiftUI
import UIKit

struct HighlightsView: View {
    @Binding var tab: AppTab
    @Binding var showSearch: Bool
    @Binding var showShorts: Bool
    @EnvironmentObject private var store: CricketStore
    @State private var category: HighlightCategory = .all

    private var clips: [HighlightClip] {
        let all = store.highlightClips
        guard category != .all else { return all }
        return all.filter { $0.category == category }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    filterRow
                    Button {
                        showShorts = true
                    } label: {
                        Text("Shorts")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Theme.magenta))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 16)
                }

                if clips.isEmpty {
                    Text("No highlights yet — paste links in OTT Admin")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                        .padding(.bottom, 28)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(clips) { clip in
                            HighlightFeedCard(clip: clip)
                                .padding(.horizontal, 16)
                                .onTapGesture {
                                    if let url = clip.videoURL {
                                        UIApplication.shared.open(url)
                                    }
                                }
                        }
                    }
                    .padding(.bottom, 28)
                }
            }
            .padding(.top, 4)
        }
        .background(Theme.background.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            AppHeader(onAvatar: { tab = .profile })
                .background(Theme.background)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color(white: 0.14)).frame(height: 1)
                }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if store.highlightClips.isEmpty {
                await store.refresh()
            }
        }
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HighlightCategory.allCases) { item in
                    Button {
                        category = item
                    } label: {
                        Text(item.label)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(category == item ? Theme.accent : Color(red: 0.07, green: 0.07, blue: 0.10))
                            )
                            .overlay(
                                Capsule().stroke(category == item ? Color.clear : Color(white: 0.15), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 16)
        }
    }
}

struct HighlightFeedCard: View {
    let clip: HighlightClip

    var body: some View {
        HStack(spacing: 12) {
            CoverImage(name: clip.imageName)
                .frame(width: 120, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(clip.tag)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Text(clip.cardTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if !clip.cardSubtitle.isEmpty {
                    Text(clip.cardSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.card)
        )
    }
}
