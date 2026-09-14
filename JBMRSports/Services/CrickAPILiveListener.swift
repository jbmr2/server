import Foundation

/// Live matches — CrickDB direct, continuous fetch (no fixed wait interval).
final class CrickAPILiveListener {
    private var task: Task<Void, Never>?
    private var activeMatchId: String?

    func start(
        matchId: String,
        matchSeq: Int?,
        onUpdate: @escaping (APICompleteMatch) -> Void,
        onMatchEnded: @escaping () -> Void
    ) {
        guard activeMatchId != matchId else { return }
        stop()
        guard !matchId.isEmpty else { return }
        activeMatchId = matchId

        task = Task { [matchId, matchSeq] in
            while !Task.isCancelled {
                do {
                    let api = try await CrickAPIClient.fetchLiveCompleteMatch(
                        matchId: matchId,
                        matchSeq: matchSeq
                    )
                    let status = api.matchInfo.status.lowercased()
                    let stillLive = status == "live" || status == "in progress"

                    await MainActor.run {
                        onUpdate(api)
                    }

                    guard stillLive else {
                        await MainActor.run { onMatchEnded() }
                        return
                    }
                } catch is CancellationError {
                    return
                } catch {
                    NSLog("JBMR CrickAPI live %@: %@", matchId, error.localizedDescription)
                }

                try? await Task.sleep(nanoseconds: LiveMatchSync.liveMatchPollIntervalNanoseconds)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        activeMatchId = nil
    }

    deinit { stop() }
}

/// Home hero — live match scores, continuous CrickDB fetch.
final class CrickAPILiveScorePoller {
    struct Target: Hashable {
        let id: String
        let matchSeq: Int?
    }

    private var task: Task<Void, Never>?
    private var targets: Set<Target> = []

    func start(
        matches: [Target],
        onUpdate: @escaping (String, APICompleteMatch) -> Void
    ) {
        let next = Set(matches)
        guard next != targets || task == nil else { return }
        stop()
        guard !next.isEmpty else { return }
        targets = next

        task = Task {
            while !Task.isCancelled {
                for target in next {
                    guard !Task.isCancelled else { return }
                    do {
                        let api = try await CrickAPIClient.fetchLiveCompleteMatch(
                            matchId: target.id,
                            matchSeq: target.matchSeq
                        )
                        let status = api.matchInfo.status.lowercased()
                        guard status == "live" || status == "in progress" else { continue }
                        await MainActor.run {
                            onUpdate(target.id, api)
                        }
                    } catch is CancellationError {
                        return
                    } catch {
                        NSLog("JBMR CrickAPI home score %@: %@", target.id, error.localizedDescription)
                    }
                }
                try? await Task.sleep(nanoseconds: LiveMatchSync.liveMatchPollIntervalNanoseconds)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        targets = []
    }

    deinit { stop() }
}
