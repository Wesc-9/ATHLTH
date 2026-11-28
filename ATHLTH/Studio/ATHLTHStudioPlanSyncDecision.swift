import Foundation

/// Deterministic three-way plan reconciliation.
/// No last-writer-wins overwrite: without a common acknowledged revision,
/// two different documents always require an explicit athlete decision.
enum ATHLTHStudioPlanSyncDecision {
    struct Acknowledgement: Codable, Hashable {
        let revision: Int64
        let fingerprint: String
    }

    enum Action: Equatable {
        case unchanged
        case upload(expectedRevision: Int64)
        case download
        case deleteRemote(expectedRevision: Int64)
        case deleteLocal
        case conflict
    }

    static func choose(
        localFingerprint: String?,
        remoteFingerprint: String?,
        remoteRevision: Int64?,
        acknowledged: Acknowledgement?
    ) -> Action {
        switch (localFingerprint, remoteFingerprint) {
        case (nil, nil):
            return .unchanged
        case (nil, .some(let remote)):
            guard let acknowledged else { return .download }
            guard let remoteRevision, remoteRevision == acknowledged.revision,
                  remote == acknowledged.fingerprint else { return .conflict }
            return .deleteRemote(expectedRevision: remoteRevision)
        case (.some(let local), nil):
            guard let acknowledged else { return .upload(expectedRevision: 0) }
            return local == acknowledged.fingerprint ? .deleteLocal : .conflict
        case let (.some(local), .some(remote)):
            if local == remote { return .unchanged }
            guard let acknowledged, let remoteRevision else { return .conflict }
            let localChanged = local != acknowledged.fingerprint
            let remoteChanged = remoteRevision != acknowledged.revision
            if localChanged && !remoteChanged {
                return .upload(expectedRevision: remoteRevision)
            }
            if remoteChanged && !localChanged { return .download }
            return .conflict
        }
    }
}
