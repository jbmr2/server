import SwiftUI

struct VideoEditorView: View {
    let clips: [ReelClipItem]
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: CricketStore
    @State private var selectedClipId: String
    @State private var showExport = false
    @State private var exporting = false
    @State private var exportProgress: Double = 0
    @State private var exportPhase = ""
    @State private var exportResult: ReelExportResult?
    @State private var exportError: String?
    @State private var resolution = "720p (HD)"
    @State private var aspect: ReelAspect = .portrait
    @State private var cropScale: CGFloat = 1
    @State private var cropOffset: CGSize = .zero
    @State private var cropBaseScale: CGFloat = 1
    @State private var cropDragStart: CGSize = .zero
    @State private var previewFrame = CGSize(width: 200, height: 356)
    @State private var overlayText = ""
    @State private var showTextAlert = false
    @State private var draftText = ""
    @State private var transition = "Fade"
    @State private var musicOn = false
    @State private var trimStart: Double = 0
    @State private var trimEnd: Double = 1
    @State private var showTrim = false
    @State private var showFullscreen = false
    @StateObject private var playback: StreamPlayback

    init(clips: [ReelClipItem]) {
        self.clips = clips
        _selectedClipId = State(initialValue: clips.dropFirst().first?.id ?? clips.first?.id ?? "")
        _playback = StateObject(wrappedValue: StreamPlayback(url: clips.first?.videoURL, autoplay: false, looping: false))
    }

    private var selectedClip: ReelClipItem? {
        clips.first { $0.id == selectedClipId } ?? clips.first
    }

    private var previewImage: String {
        selectedClip?.imageName ?? clips.first?.imageName ?? "LiveCricket"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    playerCanvas
                    filmstripSection
                    toolsRow
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }
            }
            exportPanel
        }
        .background(Color(red: 0.03, green: 0.035, blue: 0.055).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showExport) {
            if let exportResult {
                ExportShareView(result: exportResult)
            }
        }
        .overlay {
            if exporting {
                ZStack {
                    Color.black.opacity(0.6).ignoresSafeArea()
                    VStack(spacing: 14) {
                        Text(exportPhase.isEmpty ? "Exporting reel…" : exportPhase)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("\(Int(exportProgress * 100))%")
                            .font(.system(size: 36, weight: .black))
                            .foregroundStyle(Theme.accent)
                            .monospacedDigit()
                        ProgressView(value: exportProgress)
                            .tint(Theme.accent)
                            .frame(width: 220)
                        Text("\(clips.count) clips merge ho rahe hain")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(28)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
                    .padding(32)
                }
            }
        }
        .alert("Export failed", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
        .alert("Add Text", isPresented: $showTextAlert) {
            TextField("Overlay text", text: $draftText)
            Button("Save") { overlayText = draftText }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showTrim) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Trim \(selectedClip?.ballLabel ?? "clip")")
                        .font(.system(size: 16, weight: .bold))
                    Text("Start")
                    Slider(value: $trimStart, in: 0...max(trimEnd - 0.05, 0.05))
                    Text("End")
                    Slider(value: $trimEnd, in: min(trimStart + 0.05, 0.95)...1)
                    Text("Keeps \(Int((trimEnd - trimStart) * 100))% of this clip")
                        .foregroundStyle(Theme.muted)
                    Spacer()
                }
                .padding()
                .navigationTitle("Trim")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showTrim = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .fullScreenCover(isPresented: $showFullscreen) {
            FullscreenPlayerView(playback: playback, isPresented: $showFullscreen)
                .environmentObject(store)
        }
        .onChange(of: selectedClipId) { _, _ in
            if let url = selectedClip?.videoURL {
                playback.replace(url: url, autoplay: false)
            }
            resetCrop()
        }
        .onChange(of: aspect) { _, _ in
            resetCrop()
        }
        .onDisappear { playback.pause() }
    }

    private func startExport() {
        guard !exporting else { return }
        exporting = true
        exportProgress = 0
        exportPhase = "Preparing clips…"
        exportError = nil

        Task {
            do {
                let result = try await ReelExporter.export(
                    clips: clips,
                    aspect: aspect,
                    cropScale: cropScale,
                    cropOffset: cropOffset,
                    previewSize: previewFrame
                ) { value in
                    Task { @MainActor in
                        exportProgress = value
                        if value < 0.5 {
                            exportPhase = "Preparing clips…"
                        } else {
                            exportPhase = "Rendering video…"
                        }
                    }
                }
                exportResult = result
                exporting = false
                showExport = true
            } catch {
                exporting = false
                exportError = error.localizedDescription
            }
        }
    }

    private var header: some View {
        AppHeader(onLogo: { dismiss() }, showsAvatar: false)
            .background(Color(red: 0.07, green: 0.075, blue: 0.10))
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color(white: 0.13)).frame(height: 1)
            }
    }

    private func resetCrop() {
        cropScale = 1
        cropBaseScale = 1
        cropOffset = .zero
        cropDragStart = .zero
    }

    private func fittedPreview(width: CGFloat) -> CGSize {
        let maxW = max(width - 32, 120)
        let maxH: CGFloat = aspect == .portrait ? 420 : (aspect == .square ? 320 : 220)
        let r = aspect.ratio
        if maxW / maxH > r {
            return CGSize(width: maxH * r, height: maxH)
        }
        return CGSize(width: maxW, height: maxW / r)
    }

    private var playerCanvas: some View {
        GeometryReader { geo in
            let size = fittedPreview(width: geo.size.width)
            VStack(spacing: 8) {
                ZStack {
                    Color.black
                    Group {
                        if selectedClip?.videoURL != nil {
                            StreamVideoLayer(player: playback.player, videoGravity: .resizeAspectFill)
                        } else {
                            CoverImage(name: previewImage)
                        }
                    }
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(cropScale)
                    .offset(cropOffset)
                    .clipped()

                    Color.black.opacity(0.12)
                        .allowsHitTesting(false)

                    VStack {
                        HStack {
                            Text("\(playback.currentLabel) / \(playback.durationLabel)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.5)))
                            Text(aspect.rawValue)
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(.black.opacity(0.55)))
                            if !overlayText.isEmpty {
                                Text(overlayText)
                                    .font(.system(size: 11, weight: .heavy))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Theme.accent.opacity(0.85)))
                            }
                            Spacer()
                        }
                        Spacer()
                        HStack(spacing: 12) {
                            Button { playback.toggle() } label: {
                                Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                            GeometryReader { bar in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.25)).frame(height: 4)
                                    Capsule().fill(.white).frame(width: bar.size.width * playback.progress, height: 4)
                                }
                                .frame(maxHeight: .infinity)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0).onChanged { value in
                                        let f = min(max(value.location.x / max(bar.size.width, 1), 0), 1)
                                        playback.seek(fraction: f)
                                    }
                                )
                            }
                            .frame(height: 18)
                        }
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.55)))
                    }
                    .padding(10)
                }
                .frame(width: size.width, height: size.height)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.accent.opacity(0.45), lineWidth: 1.5)
                )
                .contentShape(Rectangle())
                .gesture(cropGestures)
                .onAppear { previewFrame = size }
                .onChange(of: aspect) { _, _ in previewFrame = size }

                Text("Pinch se zoom · ungli se left/right / upar-neeche shift")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity)
            .onAppear { previewFrame = size }
        }
        .frame(height: fittedPreview(width: 390).height + 28)
    }

    private var cropGestures: some Gesture {
        let drag = DragGesture()
            .onChanged { value in
                cropOffset = CGSize(
                    width: cropDragStart.width + value.translation.width,
                    height: cropDragStart.height + value.translation.height
                )
            }
            .onEnded { _ in
                cropDragStart = cropOffset
            }
        let pinch = MagnificationGesture()
            .onChanged { value in
                cropScale = min(max(cropBaseScale * value, 1), 4)
            }
            .onEnded { _ in
                cropBaseScale = cropScale
            }
        return drag.simultaneously(with: pinch)
    }

    private var filmstripSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Track Filmstrip")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(.white)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                        HStack(spacing: 4) {
                            Button {
                                selectedClipId = clip.id
                            } label: {
                                ZStack(alignment: .bottomLeading) {
                                    CoverImage(name: clip.imageName)
                                        .frame(width: 78, height: 60)
                                        .clipped()
                                    Color.black.opacity(selectedClipId == clip.id ? 0 : 0.3)
                                    VStack(alignment: .leading) {
                                        Text(clip.ballLabel)
                                            .font(.system(size: 10, weight: .black))
                                            .foregroundStyle(.white)
                                        Spacer()
                                        Text(secondsLabel(clip.duration))
                                            .font(.system(size: 9))
                                            .foregroundStyle(.white)
                                    }
                                    .padding(4)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(selectedClipId == clip.id ? Theme.accent : Color(white: 0.13),
                                                lineWidth: selectedClipId == clip.id ? 2 : 1)
                                )
                            }
                            .buttonStyle(.plain)

                            if index < clips.count - 1 {
                                Image(systemName: "arrow.left.arrow.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Theme.muted)
                                    .frame(width: 24, height: 24)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(red: 0.07, green: 0.075, blue: 0.10))
                                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(white: 0.13), lineWidth: 1))
                                    )
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            (Text("Currently trimming ")
                .foregroundStyle(Theme.muted)
             + Text(selectedClip?.ballLabel ?? "Clip")
                .foregroundStyle(Theme.magenta)
                .fontWeight(.bold)
             + Text(" • Drag edges of filmstrip to adjust play time")
                .foregroundStyle(Theme.muted))
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(16)
    }

    private var toolsRow: some View {
        HStack(spacing: 8) {
            Button { showTrim = true } label: {
                toolButton(icon: "scissors", title: "Trim")
            }
            .buttonStyle(.plain)
            Menu {
                Button("None") { transition = "None" }
                Button("Fade") { transition = "Fade" }
                Button("Slide") { transition = "Slide" }
            } label: {
                toolButton(icon: "wand.and.stars", title: "Transitions")
            }
            Button {
                draftText = overlayText
                showTextAlert = true
            } label: {
                toolButton(icon: "doc.text", title: overlayText.isEmpty ? "Add Text" : "Text ✓")
            }
            .buttonStyle(.plain)
            Button {
                musicOn.toggle()
            } label: {
                toolButton(icon: "music.note", title: musicOn ? "Music On" : "Add Music")
            }
            .buttonStyle(.plain)
        }
    }

    private func toolButton(icon: String, title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.muted)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.07, green: 0.075, blue: 0.10))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(white: 0.13), lineWidth: 1))
        )
    }

    private var exportPanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Menu {
                    Button("480p") { resolution = "480p" }
                    Button("720p (HD)") { resolution = "720p (HD)" }
                    Button("1080p (FHD)") { resolution = "1080p (FHD)" }
                } label: {
                    dropdown(label: "Resolution:", value: resolution, valueColor: .white)
                }
                Menu {
                    ForEach(ReelAspect.allCases) { item in
                        Button(item.label) { aspect = item }
                    }
                } label: {
                    dropdown(label: "Reel size:", value: aspect.label, valueColor: Theme.accent)
                }
            }

            Button { startExport() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "icloud.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                    Text(exporting ? "Exporting…" : "Export Video Reel")
                        .font(.system(size: 15, weight: .heavy))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(exporting ? Theme.muted : Theme.accent))
            }
            .buttonStyle(.plain)
            .disabled(exporting || clips.isEmpty)
        }
        .padding(16)
        .background(Color(red: 0.07, green: 0.075, blue: 0.10))
        .overlay(alignment: .top) {
            Rectangle().fill(Color(white: 0.13)).frame(height: 1)
        }
    }

    private func dropdown(label: String, value: String, valueColor: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.03, green: 0.035, blue: 0.055))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(white: 0.13), lineWidth: 1))
        )
    }

    private func secondsLabel(_ duration: String) -> String {
        let parts = duration.split(separator: ":")
        let secs = Int(parts.last ?? "0") ?? 0
        return "\(secs)s"
    }
}

private struct BackChevronTitle: View {
    @Environment(\.dismiss) private var dismiss
    let title: String

    var body: some View {
        Button { dismiss() } label: {
            HStack(spacing: 12) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 20, weight: .black))
            }
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}
