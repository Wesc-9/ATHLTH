import Foundation
import ImageIO
import Supabase
import SwiftUI
import UIKit

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

private struct ATHLTHSizedImageRequestID: Hashable {
    let url: URL
    let accountID: UUID?
    let maxPixelSize: Int?
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

private struct ATHLTHPreparedStorageImage:
    @unchecked Sendable {
    let image: UIImage
}

private enum ATHLTHStorageImageDecoder {
    static func decode(
        _ data: Data,
        maxPixelSize: Int
    ) -> ATHLTHPreparedStorageImage? {
        guard let source =
                CGImageSourceCreateWithData(
                    data as CFData,
                    nil
                )
        else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize:
                max(maxPixelSize, 64),
            kCGImageSourceShouldCacheImmediately: false
        ]

        guard let cgImage =
                CGImageSourceCreateThumbnailAtIndex(
                    source,
                    0,
                    options as CFDictionary
                )
        else {
            return nil
        }

        return ATHLTHPreparedStorageImage(
            image: UIImage(cgImage: cgImage)
        )
    }
}

@MainActor
private final class ATHLTHSizedStorageImageCache {
    static let shared =
        ATHLTHSizedStorageImageCache()

    private let images =
        NSCache<NSString, UIImage>()

    private init() {
        images.countLimit = 24
        images.totalCostLimit =
            20 * 1_024 * 1_024
    }

    func image(
        for key: String
    ) -> UIImage? {
        images.object(
            forKey: key as NSString
        )
    }

    func store(
        _ image: UIImage,
        for key: String
    ) {
        let cost =
            Int(
                image.size.width *
                image.size.height *
                image.scale *
                image.scale *
                4
            )

        images.setObject(
            image,
            forKey: key as NSString,
            cost: cost
        )
    }
}

// Use the same phase API as AsyncImage while authorizing private Storage images.
// Callers showing small artwork can opt into downsampling so a 40–100 pt avatar
// never decodes a multi-megapixel original into memory.
struct ATHLTHStorageImage<Content: View>: View {
    @Environment(\.athlthImageAccountID) private var accountID

    let url: URL?
    let maxPixelSize: Int?
    @ViewBuilder let content:
        (AsyncImagePhase) -> Content

    @State private var resolvedURL: URL?
    @State private var resolutionError: Error?
    @State private var resolvedAccountID: UUID?
    @State private var sizedImage: UIImage?

    init(
        url: URL?,
        maxPixelSize: Int? = nil,
        @ViewBuilder content:
            @escaping (AsyncImagePhase) -> Content
    ) {
        self.url = url
        self.maxPixelSize = maxPixelSize
        self.content = content
    }

    var body: some View {
        Group {
            if let maxPixelSize {
                sizedContent(
                    maxPixelSize:
                        maxPixelSize
                )
            } else if let resolutionError {
                content(
                    .failure(
                        resolutionError
                    )
                )
            } else {
                AsyncImage(
                    url:
                        resolvedAccountID ==
                            accountID
                            ? resolvedURL
                            : nil,
                    content: content
                )
                .id(accountID)
            }
        }
        .task(
            id:
                url.map {
                    ATHLTHSizedImageRequestID(
                        url: $0,
                        accountID:
                            accountID,
                        maxPixelSize:
                            maxPixelSize
                    )
                }
        ) {
            await loadImage()
        }
    }

    @ViewBuilder
    private func sizedContent(
        maxPixelSize: Int
    ) -> some View {
        if let resolutionError {
            content(
                .failure(
                    resolutionError
                )
            )
        } else if resolvedAccountID ==
                    accountID,
                  let sizedImage {
            content(
                .success(
                    Image(
                        uiImage:
                            sizedImage
                    )
                )
            )
        } else {
            content(.empty)
        }
    }

    @MainActor
    private func loadImage()
        async {
        resolvedURL = nil
        resolutionError = nil
        resolvedAccountID = nil
        sizedImage = nil

        guard let url else {
            return
        }

        do {
            let resolved =
                try await ATHLTHStorageImageURL
                    .resolve(url)

            guard !Task.isCancelled else {
                return
            }

            guard let maxPixelSize else {
                resolvedAccountID =
                    accountID
                resolvedURL =
                    resolved
                return
            }

            let isPrivate =
                ATHLTHStorageImageURL
                    .privateWorkoutPath(
                        url
                    ) != nil
            let cacheKey =
                [
                    accountID?
                        .uuidString ??
                        "anonymous",
                    String(
                        maxPixelSize
                    ),
                    url.absoluteString
                ]
                .joined(separator: "|")

            if !isPrivate,
               let cached =
                    ATHLTHSizedStorageImageCache
                        .shared
                        .image(
                            for:
                                cacheKey
                        ) {
                resolvedAccountID =
                    accountID
                sizedImage = cached
                return
            }

            var request =
                URLRequest(
                    url: resolved
                )
            if isPrivate {
                request.cachePolicy =
                    .reloadIgnoringLocalCacheData
            }

            let (data, _) =
                try await URLSession
                    .shared
                    .data(
                        for: request
                    )

            let prepared =
                await Task.detached(
                    priority: .utility
                ) {
                    ATHLTHStorageImageDecoder
                        .decode(
                            data,
                            maxPixelSize:
                                maxPixelSize
                        )
                }
                .value

            guard !Task.isCancelled,
                  let prepared
            else {
                throw URLError(
                    .cannotDecodeContentData
                )
            }

            if !isPrivate {
                ATHLTHSizedStorageImageCache
                    .shared
                    .store(
                        prepared.image,
                        for: cacheKey
                    )
            }

            resolvedAccountID =
                accountID
            sizedImage =
                prepared.image
        } catch {
            guard !Task.isCancelled else {
                return
            }
            resolutionError = error
        }
    }
}
