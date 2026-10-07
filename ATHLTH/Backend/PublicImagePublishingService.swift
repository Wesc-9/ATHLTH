import Foundation
import ImageIO
import Supabase
import UniformTypeIdentifiers

enum ATHLTHPublicImagePurpose: String, Sendable {
    case profileAvatar = "profile_avatar"
    case profileHeader = "profile_header"
    case profileGear = "profile_gear"
    case workoutMedia = "workout_media"
    case challengeCover = "challenge_cover"
    case eventCover = "event_cover"
    case clubCover = "club_cover"
    case clubHeader = "club_header"
    case clubContent = "club_content"
    case clubChatMessage = "club_chat_message"
}

struct ATHLTHPublishedPublicImage: Sendable {
    let url: URL
    let storagePath: String
}

enum ATHLTHPublicImageError: LocalizedError {
    case invalidImage
    case imageTooLarge
    case rejected
    case reviewRequired
    case moderationUnavailable
    case publicationFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return ATHLTHLocalization.choose(
                english: "ATHLTH could not read that image. Choose another photo.",
                norwegian: "ATHLTH klarte ikke å lese bildet. Velg et annet bilde."
            )
        case .imageTooLarge:
            return ATHLTHLocalization.choose(
                english: "The image is too large. Choose a smaller photo.",
                norwegian: "Bildet er for stort. Velg et mindre bilde."
            )
        case .rejected:
            return ATHLTHLocalization.choose(
                english: "This image cannot be used in a public ATHLTH surface. Choose another photo.",
                norwegian: "Dette bildet kan ikke brukes på en offentlig ATHLTH-flate. Velg et annet bilde."
            )
        case .reviewRequired:
            return ATHLTHLocalization.choose(
                english: "ATHLTH could not safely approve this image automatically. Choose another photo.",
                norwegian: "ATHLTH kunne ikke godkjenne dette bildet automatisk på en trygg måte. Velg et annet bilde."
            )
        case .moderationUnavailable:
            return ATHLTHLocalization.choose(
                english: "Image safety checking is temporarily unavailable. Try again shortly.",
                norwegian: "Sikkerhetskontrollen for bilder er midlertidig utilgjengelig. Prøv igjen om litt."
            )
        case .publicationFailed:
            return ATHLTHLocalization.choose(
                english: "ATHLTH could not publish the image. Try again.",
                norwegian: "ATHLTH klarte ikke å publisere bildet. Prøv igjen."
            )
        }
    }
}

enum ATHLTHPublicImagePublisher {
    static func publish(
        jpegData: Data,
        purpose: ATHLTHPublicImagePurpose,
        entityID: UUID? = nil,
        parentID: UUID? = nil,
        groupID: UUID? = nil,
        contentKind: String? = nil,
        client: SupabaseClient = SupabaseEnvironment.client
    ) async throws -> ATHLTHPublishedPublicImage {
        guard !jpegData.isEmpty else {
            throw ATHLTHPublicImageError.invalidImage
        }

        guard jpegData.count <= 10_485_760 else {
            throw ATHLTHPublicImageError.imageTooLarge
        }

        guard let sanitized =
                await sanitizeJPEG(
                    jpegData,
                    maxPixelSize:
                        purpose == .profileAvatar
                            ? 1_600
                            : 2_800,
                    quality:
                        purpose == .profileAvatar
                            ? 0.88
                            : 0.86
                )
        else {
            throw ATHLTHPublicImageError.invalidImage
        }

        guard sanitized.count <= 8_000_000 else {
            throw ATHLTHPublicImageError.imageTooLarge
        }

        var body: [String: String] = [
            "purpose": purpose.rawValue,
            "image_base64":
                sanitized.base64EncodedString()
        ]

        if let entityID {
            body["entity_id"] =
                entityID.uuidString.lowercased()
        }
        if let parentID {
            body["parent_id"] =
                parentID.uuidString.lowercased()
        }
        if let groupID {
            body["group_id"] =
                groupID.uuidString.lowercased()
        }
        if let contentKind {
            body["content_kind"] =
                contentKind
        }

        let response:
            ATHLTHPublicImagePublishResponse =
            try await client.functions.invoke(
                "publish-public-image",
                options:
                    FunctionInvokeOptions(
                        body: body
                    )
            )

        switch response.status {
        case "published":
            guard
                let rawURL = response.url,
                let url = URL(string: rawURL),
                let storagePath =
                    response.storagePath
            else {
                throw ATHLTHPublicImageError
                    .publicationFailed
            }

            return ATHLTHPublishedPublicImage(
                url: url,
                storagePath:
                    storagePath
            )

        case "rejected":
            throw ATHLTHPublicImageError
                .rejected

        case "review":
            throw ATHLTHPublicImageError
                .reviewRequired

        case "unavailable":
            throw ATHLTHPublicImageError
                .moderationUnavailable

        default:
            throw ATHLTHPublicImageError
                .publicationFailed
        }
    }

    private static func sanitizeJPEG(
        _ data: Data,
        maxPixelSize: Int,
        quality: CGFloat
    ) async -> Data? {
        await Task.detached(
            priority: .userInitiated
        ) {
            guard
                let source =
                    CGImageSourceCreateWithData(
                        data as CFData,
                        nil
                    )
            else {
                return nil
            }

            let options:
                [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways:
                        true,
                    kCGImageSourceCreateThumbnailWithTransform:
                        true,
                    kCGImageSourceThumbnailMaxPixelSize:
                        maxPixelSize
                ]

            guard
                let image =
                    CGImageSourceCreateThumbnailAtIndex(
                        source,
                        0,
                        options as CFDictionary
                    )
            else {
                return nil
            }

            let output =
                NSMutableData()

            guard
                let destination =
                    CGImageDestinationCreateWithData(
                        output,
                        UTType.jpeg.identifier
                            as CFString,
                        1,
                        nil
                    )
            else {
                return nil
            }

            CGImageDestinationAddImage(
                destination,
                image,
                [
                    kCGImageDestinationLossyCompressionQuality:
                        quality
                ] as CFDictionary
            )

            guard
                CGImageDestinationFinalize(
                    destination
                )
            else {
                return nil
            }

            return output as Data
        }.value
    }
}

private struct ATHLTHPublicImagePublishResponse:
    Decodable
{
    let status: String
    let url: String?
    let storagePath: String?

    enum CodingKeys: String, CodingKey {
        case status
        case url
        case storagePath =
            "storage_path"
    }
}
