import Foundation

@MainActor
final class ReelStudioStore: ObservableObject {
    static let shared = ReelStudioStore()

    @Published private(set) var clips: [ReelClipItem] = []
    @Published var toastMessage: String?

    private init() {}

    func contains(id: String) -> Bool {
        clips.contains { $0.id == id }
    }

    func toggle(delivery: BallDelivery, matchTitle: String) {
        if clips.contains(where: { $0.id == delivery.id }) {
            remove(id: delivery.id)
            toastMessage = "Reel se hata diya"
            return
        }
        add(delivery: delivery, matchTitle: matchTitle)
    }

    func add(delivery: BallDelivery, matchTitle: String) {
        guard delivery.videoURL != nil else {
            toastMessage = "Is ball pe video nahi hai"
            return
        }
        if clips.contains(where: { $0.id == delivery.id }) {
            toastMessage = "Pehle se reel me hai"
            return
        }
        let boundary: Bool = {
            if case .four = delivery.result { return true }
            if case .six = delivery.result { return true }
            return false
        }()
        clips.append(
            ReelClipItem(
                id: delivery.id,
                ballLabel: delivery.ballLabel,
                result: delivery.result.label,
                resultIsBoundary: boundary,
                match: matchTitle,
                duration: "0:08",
                imageName: delivery.imageName,
                videoURL: delivery.videoURL
            )
        )
        toastMessage = "Reel me add ho gaya ✓"
    }

    func add(_ clip: ReelClipItem) {
        guard clip.videoURL != nil else {
            toastMessage = "Video URL missing"
            return
        }
        if clips.contains(where: { $0.id == clip.id }) {
            toastMessage = "Pehle se reel me hai"
            return
        }
        clips.append(clip)
        toastMessage = "Reel me add ho gaya ✓"
    }

    func remove(id: String) {
        clips.removeAll { $0.id == id }
    }

    func move(from source: IndexSet, to destination: Int) {
        clips.move(fromOffsets: source, toOffset: destination)
    }

    func clear() {
        clips.removeAll()
    }

    func clearToast() {
        toastMessage = nil
    }
}
