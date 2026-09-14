import Foundation

#if canImport(FirebaseDatabase)
import FirebaseCore
import FirebaseDatabase

/// Admin `ott/meta/updatedAt` change hone par home/schedule refresh.
final class OTTMetaLiveListener {
    private var ref: DatabaseReference?
    private var handle: DatabaseHandle?
    private var lastValue: String?
    private(set) var isRunning = false

    func start(onUpdated: @escaping () -> Void) {
        guard FirebaseApp.app() != nil else { return }
        guard !isRunning else { return }
        let reference = FirebaseRealtime.database.reference(withPath: "ott/meta/updatedAt")
        ref = reference
        isRunning = true
        handle = reference.observe(.value) { [weak self] snapshot in
            guard let value = snapshot.value as? String, !value.isEmpty else { return }
            if self?.lastValue == value { return }
            self?.lastValue = value
            onUpdated()
        } withCancel: { [weak self] error in
            self?.isRunning = false
            NSLog("JBMR meta listener error: %@", error.localizedDescription)
        }
    }

    func stop() {
        if let handle, let ref {
            ref.removeObserver(withHandle: handle)
        }
        handle = nil
        ref = nil
        lastValue = nil
        isRunning = false
    }

    deinit { stop() }
}

#else

final class OTTMetaLiveListener {
    private(set) var isRunning = false
    func start(onUpdated: @escaping () -> Void) {}
    func stop() { isRunning = false }
}

#endif
