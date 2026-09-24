import UIKit

@MainActor
enum AppleWatchInstallSupport {
    static func openWatchApp() {
        let candidates = [
            "bridge://",
            "itms-watchs://"
        ].compactMap(URL.init(string:))

        openCandidate(candidates, at: 0)
    }

    private static func openCandidate(
        _ candidates: [URL],
        at index: Int
    ) {
        guard candidates.indices.contains(index) else {
            return
        }

        UIApplication.shared.open(
            candidates[index],
            options: [:]
        ) { opened in
            guard !opened else { return }

            Task { @MainActor in
                openCandidate(
                    candidates,
                    at: index + 1
                )
            }
        }
    }
}
