import AVFoundation
import CoreGraphics
import Foundation

enum ReelExportError: LocalizedError {
    case noClips
    case noPlayableClips
    case compositionFailed
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .noClips: return "Reel me koi clip nahi hai"
        case .noPlayableClips: return "Clips load nahi ho paye — internet check karo"
        case .compositionFailed: return "Video merge fail"
        case .exportFailed(let msg): return "Export fail: \(msg)"
        }
    }
}

enum ReelAspect: String, CaseIterable, Identifiable {
    case portrait = "9:16"
    case landscape = "16:9"
    case square = "1:1"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .portrait: return "9:16 (Portrait)"
        case .landscape: return "16:9 (Landscape)"
        case .square: return "1:1 (Square)"
        }
    }

    var ratio: CGFloat {
        switch self {
        case .portrait: return 9 / 16
        case .landscape: return 16 / 9
        case .square: return 1
        }
    }

    func renderSize(shortSide: CGFloat) -> CGSize {
        switch self {
        case .portrait: return CGSize(width: shortSide, height: shortSide * 16 / 9)
        case .landscape: return CGSize(width: shortSide * 16 / 9, height: shortSide)
        case .square: return CGSize(width: shortSide, height: shortSide)
        }
    }
}

struct ReelExportResult: Hashable {
    let fileURL: URL
    let durationSeconds: Double
    let fileSizeBytes: Int64
    let clipCount: Int
    let title: String

    var durationLabel: String {
        let total = Int(durationSeconds.rounded())
        let m = total / 60
        let s = total % 60
        return m > 0 ? String(format: "%d:%02d mins", m, s) : String(format: "0:%02d sec", s)
    }

    var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }
}

enum ReelExporter {
    static func export(
        clips: [ReelClipItem],
        aspect: ReelAspect = .portrait,
        cropScale: CGFloat = 1,
        cropOffset: CGSize = .zero,
        previewSize: CGSize = .zero,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> ReelExportResult {
        let pairs = clips.compactMap { clip -> (ReelClipItem, URL)? in
            guard let url = clip.videoURL else { return nil }
            return (clip, url)
        }
        guard !pairs.isEmpty else { throw ReelExportError.noClips }

        onProgress(0.05)

        let composition = AVMutableComposition()
        guard
            let videoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ),
            let audioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
            throw ReelExportError.compositionFailed
        }

        var cursor = CMTime.zero
        var inserted = 0
        let total = pairs.count

        for (index, pair) in pairs.enumerated() {
            let asset = AVURLAsset(url: pair.1)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let sourceVideo = videoTracks.first else { continue }

            let duration = try await asset.load(.duration)
            guard duration.isValid, duration.seconds > 0.05 else { continue }

            let range = CMTimeRange(start: .zero, duration: duration)
            try videoTrack.insertTimeRange(range, of: sourceVideo, at: cursor)

            if let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first {
                try? audioTrack.insertTimeRange(range, of: sourceAudio, at: cursor)
            }

            cursor = CMTimeAdd(cursor, duration)
            inserted += 1
            onProgress(0.05 + (Double(index + 1) / Double(total)) * 0.45)
        }

        guard inserted > 0, cursor.seconds > 0 else {
            throw ReelExportError.noPlayableClips
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("jbmr-reel-\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        try? FileManager.default.removeItem(at: outputURL)

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPreset1280x720)
            ?? AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
        else {
            throw ReelExportError.exportFailed("Exporter unavailable")
        }

        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        if let compositionLayer = try? await videoComposition(
            track: videoTrack,
            duration: cursor,
            aspect: aspect,
            cropScale: cropScale,
            cropOffset: cropOffset,
            previewSize: previewSize
        ) {
            session.videoComposition = compositionLayer
        }

        let progressTask = Task {
            while !Task.isCancelled {
                await MainActor.run {
                    onProgress(0.5 + Double(session.progress) * 0.48)
                }
                if session.progress >= 0.99 { break }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        defer { progressTask.cancel() }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously {
                continuation.resume()
            }
        }

        if let error = session.error {
            throw ReelExportError.exportFailed(error.localizedDescription)
        }
        guard session.status == .completed else {
            throw ReelExportError.exportFailed("Status \(session.status.rawValue)")
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let size = attrs[.size] as? Int64 ?? 0
        let title = pairs.first?.0.match ?? "JBMR Highlight Reel"

        onProgress(1)
        return ReelExportResult(
            fileURL: outputURL,
            durationSeconds: cursor.seconds,
            fileSizeBytes: size,
            clipCount: inserted,
            title: title
        )
    }

    private static func videoComposition(
        track: AVMutableCompositionTrack,
        duration: CMTime,
        aspect: ReelAspect,
        cropScale: CGFloat,
        cropOffset: CGSize,
        previewSize: CGSize
    ) async throws -> AVMutableVideoComposition {
        let preferred = track.preferredTransform
        let natural = try await track.load(.naturalSize)
        let oriented = natural.applying(preferred)
        let srcW = abs(oriented.width)
        let srcH = abs(oriented.height)
        let render = aspect.renderSize(shortSide: 720)
        let fill = max(render.width / max(srcW, 1), render.height / max(srcH, 1))
        let zoom = fill * max(cropScale, 1)
        var transform = preferred
            .concatenating(CGAffineTransform(scaleX: zoom, y: zoom))
        let drawnW = srcW * zoom
        let drawnH = srcH * zoom
        let previewW = max(previewSize.width, 1)
        let previewH = max(previewSize.height, 1)
        let extraX = cropOffset.width * (render.width / previewW)
        let extraY = -cropOffset.height * (render.height / previewH)
        let tx = (render.width - drawnW) / 2 + extraX
        let ty = (render.height - drawnH) / 2 + extraY
        transform = transform.concatenating(CGAffineTransform(translationX: tx, y: ty))

        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(transform, at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.layerInstructions = [layer]

        let composition = AVMutableVideoComposition()
        composition.renderSize = render
        composition.frameDuration = CMTime(value: 1, timescale: 30)
        composition.instructions = [instruction]
        return composition
    }
}
