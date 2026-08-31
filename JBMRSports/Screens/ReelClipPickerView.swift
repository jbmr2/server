import SwiftUI

/// Pick ball videos from CrickDB (complete-public) for reel studio.
struct ReelClipPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var reelStore: ReelStudioStore
    @EnvironmentObject private var store: CricketStore

    @State private var loading = true
    @State private var errorMessage: String?
    @State private var options: [ReelClipItem] = []

    var body: some View {
        List {
            if loading {
                HStack {
                    ProgressView()
                    Text("Loading CrickDB ball videos…")
                        .foregroundStyle(Theme.muted)
                }
                .listRowBackground(Theme.card)
            } else if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(Theme.liveRed)
                    .listRowBackground(Theme.card)
            } else if options.isEmpty {
                Text("CrickDB me koi ball video nahi mili")
                    .foregroundStyle(Theme.muted)
                    .listRowBackground(Theme.card)
            } else {
                ForEach(options) { clip in
                    let selected = reelStore.contains(id: clip.id)
                    Button {
                        if selected {
                            reelStore.remove(id: clip.id)
                            reelStore.toastMessage = "Reel se hata diya"
                        } else {
                            reelStore.add(clip)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(clip.ballLabel)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                                Text(clip.match)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.muted)
                                if selected {
                                    Text("In Reel")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Theme.accentBright)
                                }
                            }
                            Spacer()
                            Text(clip.result)
                                .font(.system(size: 12, weight: .black))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(Theme.accent))
                            if selected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Theme.accentBright)
                            } else {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(
                        selected ? Theme.accent.opacity(0.12) : Theme.card
                    )
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Add Deliveries")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        errorMessage = nil
        var found: [ReelClipItem] = []
        if store.scheduleMatches.isEmpty {
            await store.refresh()
        }

        await withTaskGroup(of: [ReelClipItem].self) { group in
            group.addTask {
                guard let feed = try? await FirebaseOTTClient.fetchFeed() else { return [] }
                var clips: [ReelClipItem] = []
                for t in (feed.tournaments ?? [:]).values {
                    let tName = t.name ?? "Tournament"
                    for m in (t.matches ?? [:]).values {
                        let vs = "\(m.team1?.shortName ?? m.team1?.name ?? "?") vs \(m.team2?.shortName ?? m.team2?.name ?? "?")"
                        let complete = FirebaseOTTClient.toCompleteMatch(tournament: t, match: m)
                        let minByInnings: [Int: Int] = Dictionary(grouping: complete.ballByBall, by: { $0.innings ?? 1 })
                            .mapValues { events in events.compactMap(\.overNumber).min() ?? 0 }
                        for event in complete.ballByBall {
                            guard let url = CrickAPI.absoluteURL(from: event.videoUrl) else { continue }
                            let runs = event.batRuns ?? 0
                            let wicket = event.wicket == true
                            let result = wicket ? "W" : (runs == 4 ? "4" : (runs == 6 ? "6" : "\(runs)"))
                            let minOver = minByInnings[event.innings ?? 1] ?? 0
                            clips.append(
                                ReelClipItem(
                                    id: event.id,
                                    ballLabel: "Inn \(event.innings ?? 1) · \(CricketOvers.ballLabel(overNumber: event.overNumber ?? 0, ballNumber: event.ballNumber ?? 1, minOverInInnings: minOver))",
                                    result: result,
                                    resultIsBoundary: runs == 4 || runs == 6,
                                    match: "\(tName) · \(vs)",
                                    duration: "0:08",
                                    imageName: "LiveCricket",
                                    videoURL: url
                                )
                            )
                        }
                    }
                }
                return clips
            }
            for await clips in group {
                found.append(contentsOf: clips)
            }
        }

        options = found.sorted { $0.ballLabel < $1.ballLabel }
        loading = false
    }
}
