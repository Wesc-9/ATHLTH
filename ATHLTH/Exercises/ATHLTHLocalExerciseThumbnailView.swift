import Foundation
import ImageIO
import SwiftUI
import UIKit

enum ATHLTHExerciseThumbnailSizing {
    static func pixels(points: CGFloat, scale: CGFloat) -> Int {
        guard points.isFinite, scale.isFinite, points > 0, scale > 0 else { return 64 }
        let requested = min(640, max(64, points * scale))
        return min(640, Int(ceil(requested / 32)) * 32)
    }
}

struct ATHLTHPreparedExerciseThumbnail: @unchecked Sendable {
    let image: UIImage
}

/// Background downsampling for bundled RepDB and personal exercise photos.
/// Do not open full-resolution files synchronously in every scrolling cell.
actor ATHLTHLocalExerciseThumbnailLoader {
    static let shared = ATHLTHLocalExerciseThumbnailLoader()

    private let thumbnails: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 240
        cache.totalCostLimit = 24 * 1_024 * 1_024
        return cache
    }()

    func thumbnail(for url: URL, maxPixels: Int) -> ATHLTHPreparedExerciseThumbnail? {
        guard url.isFileURL, !Task.isCancelled else { return nil }
        let pixels = max(64, min(maxPixels, 640))
        // Bundled RepDB media is immutable for the process lifetime. Avoid
        // repeated filesystem metadata queries for every cached scrolling row.
        let bundled = url.path.hasPrefix(Bundle.main.bundleURL.path + "/")
        let revision: TimeInterval
        if bundled {
            revision = 0
        } else {
            let metadata = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            revision = metadata?.contentModificationDate?.timeIntervalSince1970 ?? 0
        }
        let key = "\(url.path)|\(pixels)|\(revision)" as NSString
        if let cached = thumbnails.object(forKey: key) {
            return ATHLTHPreparedExerciseThumbnail(image: cached)
        }

        let signpost = ATHLTHPerformance.begin("ExerciseThumbnailDecode")
        defer { ATHLTHPerformance.end("ExerciseThumbnailDecode", id: signpost) }
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixels,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source, 0, options as CFDictionary
        ) else { return nil }

        guard !Task.isCancelled else { return nil }
        // Cache the already decoded display-size bitmap; do not encode
        // PNG and decode it again in the scrolling row.
        let image = UIImage(cgImage: thumbnail)
        let cost = thumbnail.bytesPerRow * thumbnail.height
        thumbnails.setObject(image, forKey: key, cost: cost)
        return ATHLTHPreparedExerciseThumbnail(image: image)
    }
}

/// Visible rows load a small thumbnail only when SwiftUI materializes them.
/// Tasks are cancelled if a cell disappears while the athlete scrolls rapidly.
struct ATHLTHLocalExerciseThumbnailView: View {
    let url: URL
    let size: CGFloat
    let fallbackSymbol: String

    @Environment(\.displayScale) private var displayScale
    @State private var thumbnail: UIImage?
    @State private var loadedRequest: Request?

    private struct Request: Hashable {
        let url: URL
        let pixels: Int
    }

    var body: some View {
        let request = Request(url: url, pixels: ATHLTHExerciseThumbnailSizing.pixels(
            points: size, scale: displayScale))
        Group {
            if let thumbnail, loadedRequest == request {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: size * 0.28))
                    .foregroundStyle(ATHLTHTheme.accent)
                    .frame(width: size, height: size)
            }
        }
        .task(id: request) {
            if loadedRequest == request, thumbnail != nil { return }
            guard let prepared = await ATHLTHLocalExerciseThumbnailLoader.shared
                .thumbnail(for: request.url, maxPixels: request.pixels),
                  !Task.isCancelled else { return }
            thumbnail = prepared.image
            loadedRequest = request
        }
    }
}
