import Combine
import Foundation
import WatchConnectivity

enum AppleWatchConnectionState: Equatable {
    case checking
    case unsupported
    case notPaired
    case appNotInstalled
    case ready

    var isReady: Bool {
        self == .ready
    }

    var subtitle: String {
        switch self {
        case .checking:
            return "Checking Apple Watch"
        case .unsupported:
            return "Apple Watch connection is unavailable on this device"
        case .notPaired:
            return "No paired Apple Watch found"
        case .appNotInstalled:
            return "ATHLTH Watch app is not installed yet"
        case .ready:
            return "Connected"
        }
    }
}

final class AppleWatchConnectionStore: NSObject, ObservableObject {
    @Published private(set) var state: AppleWatchConnectionState = .checking

    var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    override init() {
        super.init()
        refreshStatus()
    }

    var isReady: Bool {
        state.isReady
    }

    func connect() {
        refreshStatus()
    }

    func refreshStatus() {
        guard let session else {
            publish(.unsupported)
            return
        }

        session.delegate = self

        if session.activationState == .notActivated {
            publish(.checking)
            session.activate()
            return
        }

        evaluate(session)
    }

    private func evaluate(_ session: WCSession) {
        #if os(iOS)
        if !session.isPaired {
            publish(.notPaired)
        } else if !session.isWatchAppInstalled {
            publish(.appNotInstalled)
        } else {
            publish(.ready)
        }
        #else
        publish(.unsupported)
        #endif
    }

    private func publish(_ newState: AppleWatchConnectionState) {
        DispatchQueue.main.async { [weak self] in
            self?.state = newState
        }
    }
}

extension AppleWatchConnectionStore: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if error != nil {
            evaluate(session)
            return
        }

        evaluate(session)
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {
        refreshStatus()
    }

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
        refreshStatus()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        evaluate(session)
    }

    func session(
        _ session: WCSession,
        didFinish fileTransfer: WCSessionFileTransfer,
        error: Error?
    ) {
        try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
    }
    #endif
}
