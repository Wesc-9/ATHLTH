import Foundation
import Supabase
import SwiftUI

private struct ATHLTHImageAccountKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

extension EnvironmentValues {
    var athlthImageAccountID: UUID? {
        get { self[ATHLTHImageAccountKey.self] }
        set { self[ATHLTHImageAccountKey.self] = newValue }
    }
}

struct ATHLTHImageRequestID: Hashable {
    let url: URL
    let accountID: UUID?
}

enum ATHLTHStorageImageURL {
    // image_url remains a stable object locator. Never persist expiring tokens.
    static func privateWorkoutPath(_ url: URL) -> String? {
        guard url.scheme == "https",
              url.host == SupabaseEnvironment.projectURL.host else { return nil }
        let prefix = "/storage/v1/object/public/workout-media/"
        guard url.path.hasPrefix(prefix) else { return nil }
        let path = String(url.path.dropFirst(prefix.count))
        return path.isEmpty ? nil : path
    }

    static func resolve(_ url: URL) async throws -> URL {
        guard let path = privateWorkoutPath(url) else { return url }
        return try await SupabaseEnvironment.client.storage
            .from("workout-media")
            .createSignedURL(path: path, expiresIn: 60)
    }
}

// Use the same phase API as AsyncImage while authorizing private Storage images.
struct ATHLTHStorageImage<Content: View>: View {
    @Environment(\.athlthImageAccountID) private var accountID
    let url: URL?
    @ViewBuilder let content: (AsyncImagePhase) -> Content
    @State private var resolvedURL: URL?
    @State private var resolutionError: Error?
    @State private var resolvedAccountID: UUID?

    var body: some View {
        Group {
            if let resolutionError {
                content(.failure(resolutionError))
            } else {
                AsyncImage(url: resolvedAccountID == accountID ? resolvedURL : nil, content: content)
                    .id(accountID)
            }
        }
        .task(id: url.map { ATHLTHImageRequestID(url: $0, accountID: accountID) }) {
            resolvedURL = nil
            resolutionError = nil
            guard let url else { return }
            do {
                let resolved = try await ATHLTHStorageImageURL.resolve(url)
                guard !Task.isCancelled else { return }
                resolvedAccountID = accountID
                resolvedURL = resolved
            } catch {
                guard !Task.isCancelled else { return }
                resolutionError = error
            }
        }
    }
}
