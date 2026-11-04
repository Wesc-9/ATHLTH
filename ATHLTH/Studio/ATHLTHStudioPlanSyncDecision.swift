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
        case (nil, .some):
            return acknowledged == nil ? .download : .conflict
        case (.some, nil):
            return acknowledged == nil ? .upload(expectedRevision: 0) : .conflict
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
