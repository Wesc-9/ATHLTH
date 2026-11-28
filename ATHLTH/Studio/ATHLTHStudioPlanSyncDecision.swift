import Foundation

/// Three-way reconciliation. A missing cache entry is not a deletion.
/// Concurrent edits converge on the newest shared plan; ties use the
/// acknowledged server document. The store archives displaced local edits.
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
        acknowledged: Acknowledgement?,
        explicitLocalDeletion: Bool = false,
        localIsNewer: Bool = false
    ) -> Action {
        switch (localFingerprint, remoteFingerprint) {
        case (nil, nil):
            return .unchanged
        case (nil, .some(let remote)):
            guard explicitLocalDeletion, let acknowledged, let remoteRevision,
                  remoteRevision == acknowledged.revision, remote == acknowledged.fingerprint
            else { return .download }
            return .deleteRemote(expectedRevision: remoteRevision)
        case (.some, nil):
            // A previously acknowledged server document has been removed.
            // Archive an edited local copy before accepting that deletion.
            return acknowledged == nil ? .upload(expectedRevision: 0) : .deleteLocal
        case let (.some(local), .some(remote)):
            if local == remote { return .unchanged }
            guard let remoteRevision else { return .conflict }
            if let acknowledged {
                let localChanged = local != acknowledged.fingerprint
                let remoteChanged = remote != acknowledged.fingerprint || remoteRevision != acknowledged.revision
                if localChanged && !remoteChanged { return .upload(expectedRevision: remoteRevision) }
                if remoteChanged && !localChanged { return .download }
            }
            return localIsNewer ? .upload(expectedRevision: remoteRevision) : .download
        }
    }

    static func prefers(_ lhs: TrainingPlan, over rhs: TrainingPlan) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.id.uuidString > rhs.id.uuidString
    }
}
