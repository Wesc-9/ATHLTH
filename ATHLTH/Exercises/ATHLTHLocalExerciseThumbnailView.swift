import Foundation
import ImageIO
import SwiftUI
import UIKit

/// Background downsampling for bundled RepDB and personal exercise photos.
/// Do not open full-resolution files synchronously in every scrolling cell.
actor ATHLTHLocalExerciseThumbnailLoader {
    static let shared = ATHLTHLocalExerciseThumbnailLoader()

    private let thumbnails: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.countLimit = 240
        cache.totalCostLimit = 24 * 1_024 * 1_024
        return cache
    }()

    func thumbnailData(for url: URL, maxPixels: Int) -> Data? {
        guard url.isFileURL else { return nil }
        let pixels = max(64, min(maxPixels, 640))
        let key = "\(url.path)|\(pixels)" as NSString
        if let cached = thumbnails.object(forKey: key) {
            return cached as Data
        }

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

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, "public.jpeg" as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, thumbnail, [
            kCGImageDestinationLossyCompressionQuality: 0.85
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        let data = output as Data
        thumbnails.setObject(data as NSData, forKey: key, cost: data.count)
        return data
    }
}

/// Visible rows load a small thumbnail only when SwiftUI materializes them.
/// Tasks are cancelled if a cell disappears while the athlete scrolls rapidly.
struct ATHLTHLocalExerciseThumbnailView: View {
    let url: URL
    let size: CGFloat
    let fallbackSymbol: String

    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if let thumbnail {
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
        .task(id: url) {
            thumbnail = nil
            let pixels = min(640, max(64, Int(size * 3)))
            guard let data = await ATHLTHLocalExerciseThumbnailLoader.shared
                .thumbnailData(for: url, maxPixels: pixels),
                  !Task.isCancelled else { return }
            thumbnail = UIImage(data: data)
        }
    }
}
