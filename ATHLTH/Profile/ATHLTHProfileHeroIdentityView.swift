import SwiftUI

/// Shared fixed-height identity slot for own and visited profiles.
/// Name and username stay at identical positions when training focus or
/// biography are added, removed, or loaded asynchronously.
struct ATHLTHProfileHeroIdentityView: View {
    let name: String
    let username: String
    let trainingFocus: String?
    let bio: String?

    // Compact the unused bio space so the bottom-aligned hero identity
    // sits lower, clear of Dynamic Island, without moving the stat row.
    static let reservedHeight: CGFloat = 108

    private var visibleFocus: String? {
        let text = trainingFocus?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    private var visibleBio: String? {
        let text = bio?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(name)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .frame(height: 34, alignment: .leading)

            Group {
                if !username.isEmpty {
                    Text(username)
                        .foregroundStyle(.white.opacity(0.86))
                } else {
                    Color.clear
                }
            }
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(height: 23, alignment: .leading)

            Group {
                if let visibleFocus {
                    Text(visibleFocus)
                        .foregroundStyle(.white.opacity(0.92))
                } else {
                    Color.clear
                }
            }
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .frame(height: 19, alignment: .leading)

            Group {
                if let visibleBio {
                    Text(visibleBio)
                        .foregroundStyle(.white.opacity(0.88))
                } else {
                    Color.clear
                }
            }
            .font(.caption)
            .lineLimit(2)
            .frame(height: 32, alignment: .topLeading)
            .clipped()
        }
        .frame(height: Self.reservedHeight, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
