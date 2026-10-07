import Foundation
import ImageIO
import PhotosUI
import Supabase
import SwiftUI
import UIKit
import UniformTypeIdentifiers


private enum CommunityImageProcessor {
    static func prepareJPEG(
        _ data: Data,
        maxPixelSize: Int,
        quality: CGFloat
    ) async -> Data? {
        await Task.detached(
            priority: .userInitiated
        ) {
            guard let source =
                    CGImageSourceCreateWithData(
                        data as CFData,
                        nil
                    )
            else {
                return nil
            }

            let thumbnailOptions:
                [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways:
                    true,
                kCGImageSourceCreateThumbnailWithTransform:
                    true,
                kCGImageSourceThumbnailMaxPixelSize:
                    maxPixelSize,
                kCGImageSourceShouldCacheImmediately:
                    false
            ]

            guard let image =
                    CGImageSourceCreateThumbnailAtIndex(
                        source,
                        0,
                        thumbnailOptions as CFDictionary
                    )
            else {
                return nil
            }

            func encode(
                _ compression: CGFloat
            ) -> Data? {
                let output = NSMutableData()
                guard let destination =
                        CGImageDestinationCreateWithData(
                            output as CFMutableData,
                            UTType.jpeg.identifier as CFString,
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
                            compression
                    ] as CFDictionary
                )

                guard CGImageDestinationFinalize(
                    destination
                ) else {
                    return nil
                }

                return output as Data
            }

            if let encoded = encode(quality),
               encoded.count <= 5_242_880 {
                return encoded
            }

            return encode(0.62)
        }
        .value
    }
}


enum CommunityImageCropTarget:
    String,
    Identifiable {
    case clubImage
    case wideCover

    var id: String { rawValue }

    var aspectRatio: CGFloat {
        switch self {
        case .clubImage:
            return 1
        case .wideCover:
            return 16.0 / 7.0
        }
    }

    var outputSize: CGSize {
        switch self {
        case .clubImage:
            return CGSize(
                width: 1_200,
                height: 1_200
            )
        case .wideCover:
            return CGSize(
                width: 1_600,
                height: 700
            )
        }
    }

    var title: String {
        switch self {
        case .clubImage:
            return ATHLTHLocalization.choose(
                english: "Adjust Club image",
                norwegian: "Juster Club-bilde"
            )
        case .wideCover:
            return ATHLTHLocalization.choose(
                english: "Adjust cover image",
                norwegian: "Juster toppbilde"
            )
        }
    }

    var guidance: String {
        ATHLTHLocalization.choose(
            english:
                "Drag to choose the focus. Pinch or use the slider to zoom.",
            norwegian:
                "Dra bildet for å velge fokus. Knip eller bruk skyveknappen for å zoome."
        )
    }
}

struct CommunityImageCropRequest:
    Identifiable {
    let id = UUID()
    let image: UIImage
    let target: CommunityImageCropTarget
}

private extension CommunityImageProcessor {
    static func cropJPEG(
        image sourceImage: UIImage,
        viewportSize: CGSize,
        offset: CGSize,
        zoom: CGFloat,
        outputSize: CGSize,
        quality: CGFloat = 0.86
    ) -> Data? {
        guard viewportSize.width > 0,
              viewportSize.height > 0,
              outputSize.width > 0,
              outputSize.height > 0
        else {
            return nil
        }

        let image = normalizedImage(
            sourceImage
        )

        guard let cgImage = image.cgImage else {
            return nil
        }

        let sourceSize = CGSize(
            width: CGFloat(cgImage.width),
            height: CGFloat(cgImage.height)
        )

        let baseScale = max(
            viewportSize.width /
                sourceSize.width,
            viewportSize.height /
                sourceSize.height
        )
        let resolvedZoom = max(
            zoom,
            1
        )
        let displayScale =
            baseScale * resolvedZoom

        let displayedSize = CGSize(
            width:
                sourceSize.width *
                displayScale,
            height:
                sourceSize.height *
                displayScale
        )

        let maxOffsetX = max(
            0,
            (
                displayedSize.width -
                viewportSize.width
            ) / 2
        )
        let maxOffsetY = max(
            0,
            (
                displayedSize.height -
                viewportSize.height
            ) / 2
        )

        let resolvedOffsetX = min(
            max(
                offset.width,
                -maxOffsetX
            ),
            maxOffsetX
        )
        let resolvedOffsetY = min(
            max(
                offset.height,
                -maxOffsetY
            ),
            maxOffsetY
        )

        let sourceOriginX =
            (
                (
                    displayedSize.width -
                    viewportSize.width
                ) / 2 -
                resolvedOffsetX
            ) / displayScale
        let sourceOriginY =
            (
                (
                    displayedSize.height -
                    viewportSize.height
                ) / 2 -
                resolvedOffsetY
            ) / displayScale

        let sourceCropSize = CGSize(
            width:
                viewportSize.width /
                displayScale,
            height:
                viewportSize.height /
                displayScale
        )

        let sourceRect = CGRect(
            x: max(
                0,
                min(
                    sourceOriginX,
                    sourceSize.width -
                        sourceCropSize.width
                )
            ),
            y: max(
                0,
                min(
                    sourceOriginY,
                    sourceSize.height -
                        sourceCropSize.height
                )
            ),
            width: min(
                sourceCropSize.width,
                sourceSize.width
            ),
            height: min(
                sourceCropSize.height,
                sourceSize.height
            )
        )
        .integral

        guard let cropped =
                cgImage.cropping(
                    to: sourceRect
                )
        else {
            return nil
        }

        let rendererFormat =
            UIGraphicsImageRendererFormat()
        rendererFormat.scale = 1
        rendererFormat.opaque = true

        let renderer =
            UIGraphicsImageRenderer(
                size: outputSize,
                format: rendererFormat
            )

        let rendered = renderer.image {
            context in

            context.cgContext.setFillColor(
                UIColor.black.cgColor
            )
            context.cgContext.fill(
                CGRect(
                    origin: .zero,
                    size: outputSize
                )
            )

            UIImage(
                cgImage: cropped
            )
            .draw(
                in: CGRect(
                    origin: .zero,
                    size: outputSize
                )
            )
        }

        return rendered.jpegData(
            compressionQuality: quality
        )
    }

    static func normalizedImage(
        _ image: UIImage
    ) -> UIImage {
        guard image.imageOrientation != .up
        else {
            return image
        }

        let format =
            UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(
            size: image.size,
            format: format
        )
        .image { _ in
            image.draw(
                in: CGRect(
                    origin: .zero,
                    size: image.size
                )
            )
        }
    }
}

struct CommunityImageCropEditor:
    View {
    @Environment(\.dismiss)
    private var dismiss

    let request: CommunityImageCropRequest
    let onComplete: (Data) -> Void

    @State private var zoom: CGFloat = 1
    @State private var committedZoom:
        CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset:
        CGSize = .zero
    @State private var viewportSize:
        CGSize = .zero
    @State private var saving = false
    @State private var cropError:
        String?

    private var clubForest: Color {
        Color(
            red: 0.025,
            green: 0.30,
            blue: 0.21
        )
    }

    private var clubEmerald: Color {
        Color(
            red: 0.055,
            green: 0.49,
            blue: 0.32
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ATHLTHPremiumCanvas(
                    accent:
                        clubEmerald
                            .opacity(0.16)
                )
                .ignoresSafeArea()

                VStack(spacing: 18) {
                    Text(
                        request.target
                            .guidance
                    )
                    .font(.subheadline)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                    .multilineTextAlignment(
                        .center
                    )
                    .padding(
                        .horizontal,
                        24
                    )

                    cropCanvas
                        .padding(
                            .horizontal,
                            request.target ==
                                .clubImage
                                ? 46
                                : 18
                        )

                    VStack(spacing: 12) {
                        HStack {
                            Image(
                                systemName:
                                    "minus.magnifyingglass"
                            )
                            .foregroundStyle(
                                clubForest
                            )

                            Slider(
                                value: $zoom,
                                in: 1...4
                            )
                            .tint(
                                clubEmerald
                            )

                            Image(
                                systemName:
                                    "plus.magnifyingglass"
                            )
                            .foregroundStyle(
                                clubForest
                            )
                        }

                        HStack {
                            Button {
                                withAnimation(
                                    .easeInOut(
                                        duration:
                                            0.18
                                    )
                                ) {
                                    zoom = 1
                                    committedZoom =
                                        1
                                    offset = .zero
                                    committedOffset =
                                        .zero
                                }
                            } label: {
                                Label(
                                    ATHLTHLocalization
                                        .choose(
                                            english:
                                                "Reset",
                                            norwegian:
                                                "Nullstill"
                                        ),
                                    systemImage:
                                        "arrow.counterclockwise"
                                )
                            }
                            .buttonStyle(
                                .bordered
                            )
                            .tint(
                                clubForest
                            )

                            Spacer()

                            Text(
                                String(
                                    format:
                                        "%.1fx",
                                    zoom
                                )
                            )
                            .font(
                                .caption
                                    .weight(
                                        .semibold
                                    )
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .mutedText
                            )
                            .monospacedDigit()
                        }
                    }
                    .padding(
                        .horizontal,
                        22
                    )

                    Spacer(
                        minLength: 0
                    )

                    Button {
                        useCrop()
                    } label: {
                        HStack(spacing: 8) {
                            if saving {
                                ProgressView()
                                    .tint(.white)
                            }

                            Text(
                                ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Use this crop",
                                        norwegian:
                                            "Bruk dette utsnittet"
                                    )
                            )
                            .font(.headline)

                            if !saving {
                                Image(
                                    systemName:
                                        "checkmark"
                                )
                                .font(
                                    .caption.bold()
                                )
                            }
                        }
                        .foregroundStyle(
                            .white
                        )
                        .frame(
                            maxWidth:
                                .infinity
                        )
                        .frame(height: 52)
                        .background(
                            LinearGradient(
                                colors: [
                                    clubForest,
                                    clubEmerald
                                ],
                                startPoint:
                                    .leading,
                                endPoint:
                                    .trailing
                            ),
                            in:
                                RoundedRectangle(
                                    cornerRadius:
                                        18,
                                    style:
                                        .continuous
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(
                        saving ||
                        viewportSize ==
                            .zero
                    )
                    .padding(
                        .horizontal,
                        22
                    )
                    .padding(
                        .bottom,
                        14
                    )
                }
                .padding(.top, 12)
            }
            .navigationTitle(
                request.target.title
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
            .toolbar {
                ToolbarItem(
                    placement:
                        .cancellationAction
                ) {
                    Button(
                        ATHLTHLocalization
                            .choose(
                                english:
                                    "Cancel",
                                norwegian:
                                    "Avbryt"
                            )
                    ) {
                        dismiss()
                    }
                    .foregroundStyle(
                        clubForest
                    )
                }
            }
            .alert(
                ATHLTHLocalization.choose(
                    english:
                        "Could not crop image",
                    norwegian:
                        "Kunne ikke beskjære bildet"
                ),
                isPresented: Binding(
                    get: {
                        cropError != nil
                    },
                    set: {
                        if !$0 {
                            cropError = nil
                        }
                    }
                )
            ) {
                Button(
                    "OK",
                    role: .cancel
                ) {}
            } message: {
                Text(
                    cropError ?? ""
                )
            }
            .onChange(of: zoom) {
                _, newValue in

                guard viewportSize !=
                        .zero
                else {
                    return
                }

                let clamped =
                    clampedOffset(
                        offset,
                        viewport:
                            viewportSize,
                        zoom:
                            newValue
                    )

                offset = clamped
                committedOffset =
                    clamped
                committedZoom =
                    newValue
            }
        }
    }

    private var cropCanvas:
        some View {
        GeometryReader {
            geometry in

            let viewport =
                cropViewport(
                    available:
                        geometry.size
                )

            ZStack {
                Color.black
                    .opacity(0.92)

                Image(
                    uiImage:
                        request.image
                )
                .resizable()
                .scaledToFill()
                .frame(
                    width:
                        viewport.width,
                    height:
                        viewport.height
                )
                .scaleEffect(zoom)
                .offset(offset)
            }
            .frame(
                width: viewport.width,
                height:
                    viewport.height
            )
            .clipped()
            .clipShape(
                RoundedRectangle(
                    cornerRadius:
                        request.target ==
                            .clubImage
                            ? 28
                            : 22,
                    style:
                        .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius:
                        request.target ==
                            .clubImage
                            ? 28
                            : 22,
                    style:
                        .continuous
                )
                .stroke(
                    Color.white
                        .opacity(0.82),
                    lineWidth: 1.2
                )
            }
            .overlay {
                cropGrid
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius:
                                request.target ==
                                    .clubImage
                                    ? 28
                                    : 22,
                            style:
                                .continuous
                        )
                    )
            }
            .frame(
                maxWidth: .infinity,
                maxHeight:
                    .infinity
            )
            .contentShape(
                Rectangle()
            )
            .gesture(
                DragGesture()
                    .onChanged {
                        value in

                        let candidate =
                            CGSize(
                                width:
                                    committedOffset
                                        .width +
                                    value
                                        .translation
                                        .width,
                                height:
                                    committedOffset
                                        .height +
                                    value
                                        .translation
                                        .height
                            )

                        offset =
                            clampedOffset(
                                candidate,
                                viewport:
                                    viewport,
                                zoom:
                                    zoom
                            )
                    }
                    .onEnded { _ in
                        committedOffset =
                            offset
                    }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged {
                        value in

                        let next =
                            min(
                                max(
                                    committedZoom *
                                    value,
                                    1
                                ),
                                4
                            )

                        zoom = next
                        offset =
                            clampedOffset(
                                committedOffset,
                                viewport:
                                    viewport,
                                zoom:
                                    next
                            )
                    }
                    .onEnded { _ in
                        committedZoom =
                            zoom
                        committedOffset =
                            offset
                    }
            )
            .onAppear {
                viewportSize =
                    viewport
                offset =
                    clampedOffset(
                        offset,
                        viewport:
                            viewport,
                        zoom: zoom
                    )
            }
            .onChange(
                of: geometry.size
            ) { _, _ in
                viewportSize =
                    viewport
                offset =
                    clampedOffset(
                        offset,
                        viewport:
                            viewport,
                        zoom: zoom
                    )
                committedOffset =
                    offset
            }
        }
        .aspectRatio(
            request.target
                .aspectRatio,
            contentMode: .fit
        )
    }

    private var cropGrid:
        some View {
        GeometryReader {
            geometry in

            Path { path in
                let width =
                    geometry.size.width
                let height =
                    geometry.size.height

                for fraction in [
                    CGFloat(1.0 / 3.0),
                    CGFloat(2.0 / 3.0)
                ] {
                    path.move(
                        to: CGPoint(
                            x:
                                width *
                                fraction,
                            y: 0
                        )
                    )
                    path.addLine(
                        to: CGPoint(
                            x:
                                width *
                                fraction,
                            y: height
                        )
                    )

                    path.move(
                        to: CGPoint(
                            x: 0,
                            y:
                                height *
                                fraction
                        )
                    )
                    path.addLine(
                        to: CGPoint(
                            x: width,
                            y:
                                height *
                                fraction
                        )
                    )
                }
            }
            .stroke(
                Color.white
                    .opacity(0.24),
                lineWidth: 0.7
            )
        }
        .allowsHitTesting(false)
    }

    private func cropViewport(
        available: CGSize
    ) -> CGSize {
        let ratio =
            request.target
                .aspectRatio

        guard available.width > 0,
              available.height > 0
        else {
            return .zero
        }

        let widthFromHeight =
            available.height * ratio

        if widthFromHeight <=
            available.width {
            return CGSize(
                width:
                    widthFromHeight,
                height:
                    available.height
            )
        }

        return CGSize(
            width:
                available.width,
            height:
                available.width /
                ratio
        )
    }

    private func clampedOffset(
        _ candidate: CGSize,
        viewport: CGSize,
        zoom: CGFloat
    ) -> CGSize {
        let imageSize =
            request.image.size

        guard imageSize.width > 0,
              imageSize.height > 0,
              viewport.width > 0,
              viewport.height > 0
        else {
            return .zero
        }

        let baseScale = max(
            viewport.width /
                imageSize.width,
            viewport.height /
                imageSize.height
        )

        let displayedWidth =
            imageSize.width *
            baseScale *
            zoom
        let displayedHeight =
            imageSize.height *
            baseScale *
            zoom

        let maxX = max(
            0,
            (
                displayedWidth -
                viewport.width
            ) / 2
        )
        let maxY = max(
            0,
            (
                displayedHeight -
                viewport.height
            ) / 2
        )

        return CGSize(
            width: min(
                max(
                    candidate.width,
                    -maxX
                ),
                maxX
            ),
            height: min(
                max(
                    candidate.height,
                    -maxY
                ),
                maxY
            )
        )
    }

    private func useCrop() {
        guard !saving else {
            return
        }

        saving = true

        guard let data =
                CommunityImageProcessor
                    .cropJPEG(
                        image:
                            request.image,
                        viewportSize:
                            viewportSize,
                        offset:
                            offset,
                        zoom:
                            zoom,
                        outputSize:
                            request.target
                                .outputSize
                    )
        else {
            saving = false
            cropError =
                ATHLTHLocalization
                    .choose(
                        english:
                            "ATHLTH could not prepare this crop. Try another image.",
                        norwegian:
                            "ATHLTH klarte ikke å klargjøre dette utsnittet. Prøv et annet bilde."
                    )
            return
        }

        onComplete(data)
        saving = false
        dismiss()
    }
}


enum CommunityClubTheme:
    String,
    CaseIterable,
    Identifiable,
    Codable
{
    case emerald
    case ocean
    case cobalt
    case violet
    case sunset
    case ruby
    case graphite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .emerald:
            return ATHLTHLocalization.choose(english: "Emerald", norwegian: "Smaragd")
        case .ocean:
            return ATHLTHLocalization.choose(english: "Ocean", norwegian: "Hav")
        case .cobalt:
            return ATHLTHLocalization.choose(english: "Cobalt", norwegian: "Kobolt")
        case .violet:
            return ATHLTHLocalization.choose(english: "Violet", norwegian: "Fiolett")
        case .sunset:
            return ATHLTHLocalization.choose(english: "Sunset", norwegian: "Solnedgang")
        case .ruby:
            return ATHLTHLocalization.choose(english: "Ruby", norwegian: "Rubin")
        case .graphite:
            return ATHLTHLocalization.choose(english: "Graphite", norwegian: "Grafitt")
        }
    }

    var forest: Color {
        switch self {
        case .emerald: return Color(red: 0.025, green: 0.30, blue: 0.21)
        case .ocean: return Color(red: 0.02, green: 0.28, blue: 0.43)
        case .cobalt: return Color(red: 0.08, green: 0.18, blue: 0.48)
        case .violet: return Color(red: 0.24, green: 0.12, blue: 0.46)
        case .sunset: return Color(red: 0.48, green: 0.20, blue: 0.05)
        case .ruby: return Color(red: 0.46, green: 0.07, blue: 0.15)
        case .graphite: return Color(red: 0.12, green: 0.14, blue: 0.16)
        }
    }

    var emerald: Color {
        switch self {
        case .emerald: return Color(red: 0.055, green: 0.49, blue: 0.32)
        case .ocean: return Color(red: 0.02, green: 0.48, blue: 0.64)
        case .cobalt: return Color(red: 0.13, green: 0.38, blue: 0.78)
        case .violet: return Color(red: 0.44, green: 0.27, blue: 0.72)
        case .sunset: return Color(red: 0.86, green: 0.39, blue: 0.08)
        case .ruby: return Color(red: 0.78, green: 0.12, blue: 0.28)
        case .graphite: return Color(red: 0.28, green: 0.31, blue: 0.34)
        }
    }

    var leaf: Color {
        switch self {
        case .emerald: return Color(red: 0.18, green: 0.62, blue: 0.35)
        case .ocean: return Color(red: 0.16, green: 0.68, blue: 0.76)
        case .cobalt: return Color(red: 0.22, green: 0.52, blue: 0.94)
        case .violet: return Color(red: 0.63, green: 0.40, blue: 0.86)
        case .sunset: return Color(red: 0.96, green: 0.58, blue: 0.18)
        case .ruby: return Color(red: 0.91, green: 0.30, blue: 0.45)
        case .graphite: return Color(red: 0.44, green: 0.48, blue: 0.52)
        }
    }

    var mint: Color {
        switch self {
        case .emerald: return Color(red: 0.90, green: 0.96, blue: 0.92)
        case .ocean: return Color(red: 0.90, green: 0.97, blue: 0.98)
        case .cobalt: return Color(red: 0.91, green: 0.94, blue: 0.99)
        case .violet: return Color(red: 0.95, green: 0.92, blue: 0.99)
        case .sunset: return Color(red: 0.99, green: 0.94, blue: 0.88)
        case .ruby: return Color(red: 0.99, green: 0.91, blue: 0.93)
        case .graphite: return Color(red: 0.94, green: 0.95, blue: 0.96)
        }
    }

    var sage: Color {
        switch self {
        case .emerald: return Color(red: 0.77, green: 0.88, blue: 0.81)
        case .ocean: return Color(red: 0.74, green: 0.88, blue: 0.91)
        case .cobalt: return Color(red: 0.77, green: 0.83, blue: 0.94)
        case .violet: return Color(red: 0.84, green: 0.78, blue: 0.93)
        case .sunset: return Color(red: 0.94, green: 0.82, blue: 0.70)
        case .ruby: return Color(red: 0.93, green: 0.75, blue: 0.80)
        case .graphite: return Color(red: 0.82, green: 0.84, blue: 0.86)
        }
    }

    var gradient: LinearGradient {
        LinearGradient(
            colors: [forest, emerald, leaf],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct CommunityGroupRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let creatorID: UUID
    let name: String
    let summary: String
    let locationName: String
    let visibility: String
    let imageURL: String?
    let headerImageURL: String?
    let featuredChallengeID: UUID?
    let joinMode: String
    let membersCanCreateContent: Bool
    var themeKey: String? = nil
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case creatorID = "creator_id"
        case name
        case summary
        case locationName = "location_name"
        case visibility
        case imageURL = "image_url"
        case headerImageURL = "header_image_url"
        case featuredChallengeID = "featured_challenge_id"
        case joinMode = "join_mode"
        case membersCanCreateContent = "members_can_create_content"
        case themeKey = "theme_key"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

extension CommunityGroupRecord {
    var clubTheme: CommunityClubTheme {
        CommunityClubTheme(rawValue: themeKey ?? "") ?? .emerald
    }
}

struct CommunityGroupMemberRecord: Codable, Hashable {
    let groupID: UUID
    let userID: UUID
    let role: String
    let joinedAt: Date

    enum CodingKeys: String, CodingKey {
        case groupID = "group_id"
        case userID = "user_id"
        case role
        case joinedAt = "joined_at"
    }
}

struct CommunityGroupAnnouncementRecord:
    Codable,
    Identifiable,
    Hashable
{
    let id: UUID
    let groupID: UUID
    let authorID: UUID
    let body: String
    let pinnedAt: Date?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case groupID = "group_id"
        case authorID = "author_id"
        case body
        case pinnedAt = "pinned_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct CommunityGroupAnnouncementReactionRecord:
    Codable,
    Hashable
{
    let announcementID: UUID
    let groupID: UUID
    let userID: UUID
    let reaction: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case announcementID = "announcement_id"
        case groupID = "group_id"
        case userID = "user_id"
        case reaction
        case createdAt = "created_at"
    }
}

struct CommunityGroupEngagementLeaderboardEntry:
    Codable,
    Identifiable,
    Hashable
{
    var id: UUID { userID }

    let userID: UUID
    let workoutCount: Int
    let messageCount: Int
    let likesGiven: Int
    let eventsJoined: Int
    let challengesJoined: Int
    let score: Int

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case workoutCount = "workout_count"
        case messageCount = "message_count"
        case likesGiven = "likes_given"
        case eventsJoined = "events_joined"
        case challengesJoined = "challenges_joined"
        case score
    }
}

struct CommunityGroupActivityRecord:
    Codable,
    Identifiable,
    Hashable
{
    let id: UUID
    let groupID: UUID
    let actorID: UUID?
    let kind: String
    let entityID: UUID?
    let headline: String
    let detail: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case groupID = "group_id"
        case actorID = "actor_id"
        case kind
        case entityID = "entity_id"
        case headline
        case detail
        case createdAt = "created_at"
    }
}

struct CommunityGroupMessageRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let groupID: UUID
    let senderID: UUID
    let senderName: String
    let body: String
    var imageURL: String? = nil
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case groupID = "group_id"
        case senderID = "sender_id"
        case senderName = "sender_name"
        case body
        case imageURL = "image_url"
        case createdAt = "created_at"
    }
}

struct CommunityGroupEventRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let groupID: UUID
    let creatorID: UUID
    let title: String
    let summary: String
    let activityType: String
    let startsAt: Date
    let endsAt: Date?
    let meetingName: String
    let imageURL: String?
    let activityConfiguration:
        CommunityGroupActivityConfiguration?
    let status: String
    let organizerKind: CommunityGroupOrganizerKind
    let organizerUserID: UUID?
    let capacity: Int?
    let rsvpDeadline: Date?
    let meetingLatitude: Double?
    let meetingLongitude: Double?
    let repeatRule: String?
    let repeatUntil: Date?
    let seriesID: UUID?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case groupID = "group_id"
        case creatorID = "creator_id"
        case title
        case summary
        case activityType = "activity_type"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case meetingName = "meeting_name"
        case imageURL = "image_url"
        case activityConfiguration = "activity_config"
        case status
        case organizerKind = "organizer_kind"
        case organizerUserID = "organizer_user_id"
        case capacity
        case rsvpDeadline = "rsvp_deadline"
        case meetingLatitude = "meeting_lat"
        case meetingLongitude = "meeting_long"
        case repeatRule = "repeat_rule"
        case repeatUntil = "repeat_until"
        case seriesID = "series_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum CommunityGroupChallengeMetric: String, Codable, CaseIterable, Identifiable {
    case distanceKM = "distance_km"
    case workouts
    case activeMinutes = "active_minutes"
    case fastestTime = "fastest_time_seconds"
    case strengthVolume = "strength_volume_kg"
    case heaviestWeight = "heaviest_weight_kg"
    case strengthReps = "strength_reps"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .distanceKM: return "Distance"
        case .workouts: return "Workouts"
        case .activeMinutes: return "Active Minutes"
        case .fastestTime: return "Fastest Time"
        case .strengthVolume: return "Total Volume"
        case .heaviestWeight: return "Heaviest Weight"
        case .strengthReps: return "Total Reps"
        }
    }

    var unit: String {
        switch self {
        case .distanceKM: return "km"
        case .workouts: return "workouts"
        case .activeMinutes: return "min"
        case .fastestTime: return "time"
        case .strengthVolume: return "kg"
        case .heaviestWeight: return "kg"
        case .strengthReps: return "reps"
        }
    }

    var icon: String {
        switch self {
        case .distanceKM: return "figure.run"
        case .workouts: return "checkmark.circle.fill"
        case .activeMinutes: return "clock.fill"
        case .fastestTime: return "timer"
        case .strengthVolume: return "sum"
        case .heaviestWeight: return "dumbbell.fill"
        case .strengthReps: return "repeat"
        }
    }
}

struct CommunityGroupChallengeRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let groupID: UUID
    let creatorID: UUID
    let title: String
    let summary: String
    let metric: CommunityGroupChallengeMetric
    let targetValue: Double
    let startsAt: Date
    let endsAt: Date
    let imageURL: String?
    let activityConfiguration:
        CommunityGroupActivityConfiguration?
    let status: String
    let organizerKind: CommunityGroupOrganizerKind
    let organizerUserID: UUID?
    let scoringMode: CommunityGroupScoringMode
    let attemptLimit: Int?
    let routeVerificationEnabled: Bool
    let routeToleranceMeters: Int
    let joinRequired: Bool
    let seriesID: UUID?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case groupID = "group_id"
        case creatorID = "creator_id"
        case title
        case summary
        case metric
        case targetValue = "target_value"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case imageURL = "image_url"
        case activityConfiguration = "activity_config"
        case status
        case organizerKind = "organizer_kind"
        case organizerUserID = "organizer_user_id"
        case scoringMode = "scoring_mode"
        case attemptLimit = "attempt_limit"
        case routeVerificationEnabled =
            "route_verification_enabled"
        case routeToleranceMeters =
            "route_tolerance_meters"
        case joinRequired = "join_required"
        case seriesID = "series_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct CommunityGroupChallengeWorkoutRecord: Codable, Hashable {
    let challengeID: UUID
    let userID: UUID
    let workoutID: UUID
    let contribution: Double
    let routeMatchPercent: Double?
    let verificationStatus: String
    let isManual: Bool
    let manualNote: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case challengeID = "challenge_id"
        case userID = "user_id"
        case workoutID = "workout_id"
        case contribution
        case routeMatchPercent = "route_match_percent"
        case verificationStatus = "verification_status"
        case isManual = "is_manual"
        case manualNote = "manual_note"
        case createdAt = "created_at"
    }
}

struct CommunityGroupJoinRequestRecord: Codable, Hashable {
    let groupID: UUID
    let userID: UUID
    let status: String
    let createdAt: Date
    let respondedAt: Date?
    let respondedBy: UUID?

    enum CodingKeys: String, CodingKey {
        case groupID = "group_id"
        case userID = "user_id"
        case status
        case createdAt = "created_at"
        case respondedAt = "responded_at"
        case respondedBy = "responded_by"
    }
}

struct CommunityGroupInviteRecord: Codable, Hashable {
    let groupID: UUID
    let userID: UUID
    let invitedBy: UUID
    let status: String
    let createdAt: Date
    let respondedAt: Date?

    enum CodingKeys: String, CodingKey {
        case groupID = "group_id"
        case userID = "user_id"
        case invitedBy = "invited_by"
        case status
        case createdAt = "created_at"
        case respondedAt = "responded_at"
    }
}

struct CommunityGroupNotificationPreferenceRecord: Codable, Hashable {
    let groupID: UUID
    let userID: UUID
    let mode: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case groupID = "group_id"
        case userID = "user_id"
        case mode
        case updatedAt = "updated_at"
    }
}

struct CommunityGroupEventRSVPRecord: Codable, Hashable {
    let groupID: UUID
    let eventID: UUID
    let userID: UUID
    let status: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case groupID = "group_id"
        case eventID = "event_id"
        case userID = "user_id"
        case status
        case updatedAt = "updated_at"
    }
}

private struct CommunityGroupInsert: Encodable {
    let id: UUID
    let creatorID: UUID
    let name: String
    let summary: String
    let locationName: String
    let visibility: String
    let joinMode: String
    let membersCanCreateContent: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case creatorID = "creator_id"
        case name
        case summary
        case locationName = "location_name"
        case visibility
        case joinMode = "join_mode"
        case membersCanCreateContent = "members_can_create_content"
    }
}

private struct CommunityGroupUpdate: Encodable {
    let name: String
    let summary: String
    let locationName: String
    let visibility: String
    let joinMode: String
    let membersCanCreateContent: Bool
    let themeKey: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case name
        case summary
        case locationName = "location_name"
        case visibility
        case joinMode = "join_mode"
        case membersCanCreateContent = "members_can_create_content"
        case themeKey = "theme_key"
        case updatedAt = "updated_at"
    }
}

private struct CommunityGroupImageUpdate: Encodable {
    let imageURL: String?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case imageURL = "image_url"
        case updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var container =
            encoder.container(keyedBy: CodingKeys.self)

        if let imageURL {
            try container.encode(
                imageURL,
                forKey: .imageURL
            )
        } else {
            try container.encodeNil(
                forKey: .imageURL
            )
        }

        try container.encode(
            updatedAt,
            forKey: .updatedAt
        )
    }
}

private struct CommunityGroupHeaderImageUpdate: Encodable {
    let headerImageURL: String?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case headerImageURL = "header_image_url"
        case updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var container =
            encoder.container(keyedBy: CodingKeys.self)

        if let headerImageURL {
            try container.encode(
                headerImageURL,
                forKey: .headerImageURL
            )
        } else {
            try container.encodeNil(
                forKey: .headerImageURL
            )
        }

        try container.encode(
            updatedAt,
            forKey: .updatedAt
        )
    }
}

private struct CommunityGroupFeaturedChallengeUpdate: Encodable {
    let featuredChallengeID: UUID?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case featuredChallengeID = "featured_challenge_id"
        case updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var container =
            encoder.container(keyedBy: CodingKeys.self)

        if let featuredChallengeID {
            try container.encode(
                featuredChallengeID,
                forKey: .featuredChallengeID
            )
        } else {
            try container.encodeNil(
                forKey: .featuredChallengeID
            )
        }

        try container.encode(
            updatedAt,
            forKey: .updatedAt
        )
    }
}

private struct CommunityGroupAnnouncementInsert: Encodable {
    let groupID: UUID
    let authorID: UUID
    let body: String

    enum CodingKeys: String, CodingKey {
        case groupID = "group_id"
        case authorID = "author_id"
        case body
    }
}

private struct CommunityGroupAnnouncementReactionInsert: Encodable {
    let announcementID: UUID
    let groupID: UUID
    let userID: UUID
    let reaction: String

    enum CodingKeys: String, CodingKey {
        case announcementID = "announcement_id"
        case groupID = "group_id"
        case userID = "user_id"
        case reaction
    }
}

private struct CommunityGroupLeaderboardParams: Encodable {
    let groupID: UUID

    enum CodingKeys: String, CodingKey {
        case groupID = "p_group_id"
    }
}

private struct CommunityGroupWorkoutActivityParams: Encodable {
    let workoutID: UUID
    let completedAt: Date

    enum CodingKeys: String, CodingKey {
        case workoutID = "p_workout_id"
        case completedAt = "p_completed_at"
    }
}

private struct CommunityGroupMemberInsert: Encodable {
    let groupID: UUID
    let userID: UUID
    let role: String

    enum CodingKeys: String, CodingKey {
        case groupID = "group_id"
        case userID = "user_id"
        case role
    }
}

private struct CommunityGroupMessageInsert: Encodable {
    let id: UUID
    let groupID: UUID
    let senderID: UUID
    let senderName: String
    let body: String
    let imageURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case groupID = "group_id"
        case senderID = "sender_id"
        case senderName = "sender_name"
        case body
        case imageURL = "image_url"
    }
}

private struct CommunityGroupEventInsert: Encodable {
    let id: UUID
    let groupID: UUID
    let creatorID: UUID
    let title: String
    let summary: String
    let activityType: String
    let startsAt: Date
    let endsAt: Date?
    let meetingName: String
    let imageURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case groupID = "group_id"
        case creatorID = "creator_id"
        case title
        case summary
        case activityType = "activity_type"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case meetingName = "meeting_name"
        case imageURL = "image_url"
    }
}

private struct CommunityGroupChallengeInsert: Encodable {
    let id: UUID
    let groupID: UUID
    let creatorID: UUID
    let title: String
    let summary: String
    let metric: CommunityGroupChallengeMetric
    let targetValue: Double
    let startsAt: Date
    let endsAt: Date
    let imageURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case groupID = "group_id"
        case creatorID = "creator_id"
        case title
        case summary
        case metric
        case targetValue = "target_value"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case imageURL = "image_url"
    }
}

private struct CommunityGroupEventCreateParams: Encodable {
    let id: UUID
    let groupID: UUID
    let title: String
    let summary: String
    let activityType: String
    let startsAt: Date
    let meetingName: String
    let imageURL: String?
    let activityConfiguration:
        CommunityGroupActivityConfiguration?

    enum CodingKeys: String, CodingKey {
        case id = "p_id"
        case groupID = "p_group_id"
        case title = "p_title"
        case summary = "p_summary"
        case activityType = "p_activity_type"
        case startsAt = "p_starts_at"
        case meetingName = "p_meeting_name"
        case imageURL = "p_image_url"
        case activityConfiguration =
            "p_activity_config"
    }
}

private struct CommunityGroupChallengeCreateParams: Encodable {
    let id: UUID
    let groupID: UUID
    let title: String
    let summary: String
    let metric: String
    let targetValue: Double
    let startsAt: Date
    let endsAt: Date
    let imageURL: String?
    let activityConfiguration:
        CommunityGroupActivityConfiguration?

    enum CodingKeys: String, CodingKey {
        case id = "p_id"
        case groupID = "p_group_id"
        case title = "p_title"
        case summary = "p_summary"
        case metric = "p_metric"
        case targetValue = "p_target_value"
        case startsAt = "p_starts_at"
        case endsAt = "p_ends_at"
        case imageURL = "p_image_url"
        case activityConfiguration =
            "p_activity_config"
    }
}

private struct CommunityGroupEventCreateV2Params: Encodable {
    let id: UUID
    let groupID: UUID
    let title: String
    let summary: String
    let activityType: String
    let startsAt: Date
    let meetingName: String
    let imageURL: String?
    let activityConfiguration:
        CommunityGroupActivityConfiguration?
    let options: CommunityGroupEventAdvancedOptions

    enum CodingKeys: String, CodingKey {
        case id = "p_id"
        case groupID = "p_group_id"
        case title = "p_title"
        case summary = "p_summary"
        case activityType = "p_activity_type"
        case startsAt = "p_starts_at"
        case meetingName = "p_meeting_name"
        case imageURL = "p_image_url"
        case activityConfiguration =
            "p_activity_config"
        case options = "p_options"
    }
}

private struct CommunityGroupChallengeCreateV2Params: Encodable {
    let id: UUID
    let groupID: UUID
    let title: String
    let summary: String
    let metric: String
    let targetValue: Double
    let startsAt: Date
    let endsAt: Date
    let imageURL: String?
    let activityConfiguration:
        CommunityGroupActivityConfiguration?
    let options: CommunityGroupChallengeAdvancedOptions

    enum CodingKeys: String, CodingKey {
        case id = "p_id"
        case groupID = "p_group_id"
        case title = "p_title"
        case summary = "p_summary"
        case metric = "p_metric"
        case targetValue = "p_target_value"
        case startsAt = "p_starts_at"
        case endsAt = "p_ends_at"
        case imageURL = "p_image_url"
        case activityConfiguration =
            "p_activity_config"
        case options = "p_options"
    }
}

private struct CommunityGroupChallengeWorkoutInsert: Encodable {
    let challengeID: UUID
    let userID: UUID
    let workoutID: UUID
    let contribution: Double
    let routeMatchPercent: Double?
    let verificationStatus: String

    enum CodingKeys: String, CodingKey {
        case challengeID = "challenge_id"
        case userID = "user_id"
        case workoutID = "workout_id"
        case contribution
        case routeMatchPercent = "route_match_percent"
        case verificationStatus = "verification_status"
    }
}

private struct CommunityGroupAnnouncementPinParams: Encodable {
    let groupID: UUID
    let announcementID: UUID?

    enum CodingKeys: String, CodingKey {
        case groupID = "p_group_id"
        case announcementID = "p_announcement_id"
    }
}

private struct CommunityGroupJoinParams: Encodable {
    let groupID: UUID

    enum CodingKeys: String, CodingKey {
        case groupID = "p_group_id"
    }
}

private struct CommunityGroupJoinResponseParams: Encodable {
    let groupID: UUID
    let userID: UUID
    let accept: Bool

    enum CodingKeys: String, CodingKey {
        case groupID = "p_group_id"
        case userID = "p_user_id"
        case accept = "p_accept"
    }
}

private struct CommunityGroupInviteParams: Encodable {
    let groupID: UUID
    let userID: UUID

    enum CodingKeys: String, CodingKey {
        case groupID = "p_group_id"
        case userID = "p_user_id"
    }
}

private struct CommunityGroupInviteResponseParams: Encodable {
    let groupID: UUID
    let accept: Bool

    enum CodingKeys: String, CodingKey {
        case groupID = "p_group_id"
        case accept = "p_accept"
    }
}

@MainActor
final class CommunityGroupStore: ObservableObject {
    @Published private(set) var groups: [CommunityGroupRecord] = []
    @Published private(set) var searchResults: [CommunityGroupRecord] = []
    @Published private(set) var ownMemberships: [CommunityGroupMemberRecord] = []
    @Published private(set) var membersByGroup: [UUID: [CommunityGroupMemberRecord]] = [:]
    @Published private(set) var announcementsByGroup: [UUID: [CommunityGroupAnnouncementRecord]] = [:]
    @Published private(set) var announcementReactionsByGroup: [UUID: [CommunityGroupAnnouncementReactionRecord]] = [:]
    @Published private(set) var announcementCommentsByGroup: [UUID: [CommunityGroupContentCommentRecord]] = [:]
    @Published private(set) var activityByGroup: [UUID: [CommunityGroupActivityRecord]] = [:]
    @Published private(set) var communityActivity: [CommunityGroupActivityRecord] = []
    @Published private(set) var profileCardsByID: [UUID: SocialProfileCard] = [:]
    @Published private(set) var messagesByGroup: [UUID: [CommunityGroupMessageRecord]] = [:]
    @Published private(set) var eventsByGroup: [UUID: [CommunityGroupEventRecord]] = [:]
    @Published private(set) var challengesByGroup: [UUID: [CommunityGroupChallengeRecord]] = [:]
    @Published private(set) var challengeWorkouts: [CommunityGroupChallengeWorkoutRecord] = []
    @Published private(set) var joinRequestsByGroup: [UUID: [CommunityGroupJoinRequestRecord]] = [:]
    @Published private(set) var ownJoinRequests: [CommunityGroupJoinRequestRecord] = []
    @Published private(set) var ownInvites: [CommunityGroupInviteRecord] = []
    @Published private(set) var notificationPreferencesByGroup: [UUID: CommunityGroupNotificationPreferenceRecord] = [:]
    @Published private(set) var eventRSVPsByGroup: [UUID: [CommunityGroupEventRSVPRecord]] = [:]
    @Published private(set) var leaderboardByGroup: [UUID: [CommunityGroupEngagementLeaderboardEntry]] = [:]
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let client: SupabaseClient
    private var lastRefreshAt: Date?
    private var groupFetchLimit = 40
    @Published private(set) var canLoadMoreGroups = true
    @Published private(set) var isLoadingMoreGroups = false

    init(client: SupabaseClient = SupabaseEnvironment.client) {
        self.client = client
    }

    private var currentUserID: UUID? {
        client.auth.currentUser?.id
    }

    var joinedGroupIDs: Set<UUID> {
        Set(ownMemberships.map(\.groupID))
    }

    var joinedGroups: [CommunityGroupRecord] {
        groups.filter { joinedGroupIDs.contains($0.id) }
    }

    func isMember(of group: CommunityGroupRecord) -> Bool {
        joinedGroupIDs.contains(group.id)
    }

    func isOwner(of group: CommunityGroupRecord) -> Bool {
        group.creatorID == currentUserID
    }

    func canManage(_ group: CommunityGroupRecord) -> Bool {
        if isOwner(of: group) {
            return true
        }

        return ownMemberships.contains {
            $0.groupID == group.id &&
            ($0.role == "owner" || $0.role == "admin")
        }
    }

    func canPublishUpdates(_ group: CommunityGroupRecord) -> Bool {
        if canManage(group) {
            return true
        }

        return ownMemberships.contains {
            $0.groupID == group.id &&
            $0.role == "contributor"
        }
    }

    func role(in group: CommunityGroupRecord) -> String? {
        if isOwner(of: group) {
            return "owner"
        }

        return ownMemberships.first {
            $0.groupID == group.id
        }?.role
    }

    func canCreateGroupContent(
        _ group: CommunityGroupRecord
    ) -> Bool {
        switch role(in: group) {
        case "owner", "admin", "contributor":
            return true
        case "member":
            return group.membersCanCreateContent
        default:
            return false
        }
    }

    func profileCard(for userID: UUID) -> SocialProfileCard? {
        profileCardsByID[userID]
    }

    func group(for groupID: UUID) -> CommunityGroupRecord? {
        groups.first { $0.id == groupID }
    }

    func members(in groupID: UUID) -> [CommunityGroupMemberRecord] {
        var resolved = membersByGroup[groupID] ?? []

        // The creator is always the Club owner in the backend. Surface that
        // immediately even if the detailed membership query is still loading,
        // so a freshly created Club never shows an empty Members screen.
        if let group = group(for: groupID),
           !resolved.contains(
               where: { $0.userID == group.creatorID }
           ) {
            resolved.insert(
                CommunityGroupMemberRecord(
                    groupID: groupID,
                    userID: group.creatorID,
                    role: "owner",
                    joinedAt: group.createdAt
                ),
                at: 0
            )
        }

        return resolved
    }

    func announcements(
        in groupID: UUID
    ) -> [CommunityGroupAnnouncementRecord] {
        announcementsByGroup[groupID] ?? []
    }

    func announcementLikeCount(
        _ announcementID: UUID,
        in groupID: UUID
    ) -> Int {
        announcementReactionsByGroup[groupID]?
            .filter {
                $0.announcementID == announcementID &&
                $0.reaction == "like"
            }
            .count ?? 0
    }

    func hasLikedAnnouncement(
        _ announcementID: UUID,
        in groupID: UUID
    ) -> Bool {
        guard let currentUserID else { return false }

        return announcementReactionsByGroup[groupID]?
            .contains {
                $0.announcementID == announcementID &&
                $0.userID == currentUserID &&
                $0.reaction == "like"
            } ?? false
    }

    func announcementComments(
        for announcementID: UUID,
        in groupID: UUID
    ) -> [CommunityGroupContentCommentRecord] {
        (announcementCommentsByGroup[groupID] ?? [])
            .filter {
                $0.contentType == "announcement" &&
                $0.contentID == announcementID
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func announcementCommentCount(
        _ announcementID: UUID,
        in groupID: UUID
    ) -> Int {
        announcementComments(for: announcementID, in: groupID).count
    }

    func leaderboard(
        in groupID: UUID
    ) -> [CommunityGroupEngagementLeaderboardEntry] {
        leaderboardByGroup[groupID] ?? []
    }

    func activity(
        in groupID: UUID
    ) -> [CommunityGroupActivityRecord] {
        activityByGroup[groupID] ?? []
    }

    func messages(in groupID: UUID) -> [CommunityGroupMessageRecord] {
        messagesByGroup[groupID] ?? []
    }

    func events(in groupID: UUID) -> [CommunityGroupEventRecord] {
        eventsByGroup[groupID] ?? []
    }

    func challenges(in groupID: UUID) -> [CommunityGroupChallengeRecord] {
        challengesByGroup[groupID] ?? []
    }

    func joinRequests(
        in groupID: UUID
    ) -> [CommunityGroupJoinRequestRecord] {
        joinRequestsByGroup[groupID] ?? []
    }

    func pendingJoinRequest(
        for groupID: UUID
    ) -> CommunityGroupJoinRequestRecord? {
        ownJoinRequests.first {
            $0.groupID == groupID &&
            $0.status == "pending"
        }
    }

    func pendingInvite(
        for groupID: UUID
    ) -> CommunityGroupInviteRecord? {
        ownInvites.first {
            $0.groupID == groupID &&
            $0.status == "pending"
        }
    }

    func notificationMode(in groupID: UUID) -> String {
        notificationPreferencesByGroup[groupID]?.mode
            ?? "all"
    }

    func pinnedAnnouncement(
        in groupID: UUID
    ) -> CommunityGroupAnnouncementRecord? {
        announcements(in: groupID).first {
            $0.pinnedAt != nil
        }
    }

    func eventRSVP(
        eventID: UUID
    ) -> CommunityGroupEventRSVPRecord? {
        for values in eventRSVPsByGroup.values {
            if let value = values.first(where: {
                $0.eventID == eventID &&
                $0.userID == currentUserID
            }) {
                return value
            }
        }
        return nil
    }

    func eventRSVPCount(
        eventID: UUID,
        status: String
    ) -> Int {
        eventRSVPsByGroup.values
            .flatMap { $0 }
            .filter {
                $0.eventID == eventID &&
                $0.status == status
            }
            .count
    }

    func mentionCandidates(
        in groupID: UUID
    ) -> [SocialProfileCard] {
        members(in: groupID).compactMap {
            profileCardsByID[$0.userID]
        }
    }

    func challengeProgress(
        _ challenge: CommunityGroupChallengeRecord
    ) -> Double {
        let values = challengeWorkouts.filter {
            $0.challengeID == challenge.id &&
            $0.verificationStatus != "unverified"
        }

        switch challenge.scoringMode {
        case .cumulative:
            return values.reduce(0) {
                $0 + $1.contribution
            }

        case .bestAttempt:
            let scores = values.map(\.contribution)
            guard !scores.isEmpty else {
                return 0
            }

            if challenge.prefersLowerLeaderboardScore {
                return scores.min() ?? 0
            }

            return scores.max() ?? 0

        case .completeTarget:
            return min(
                values.reduce(0) {
                    $0 + $1.contribution
                },
                challenge.targetValue
            )
        }
    }

    func search(_ query: String) async {
        let requestedQuery = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard requestedQuery.count >= 2,
              currentUserID != nil
        else {
            searchResults = []
            return
        }

        let pattern = "%\(requestedQuery)%"

        do {
            async let nameRows: [CommunityGroupRecord] = client
                .from("community_groups")
                .select()
                .ilike("name", pattern: pattern)
                .limit(20)
                .execute()
                .value

            async let locationRows: [CommunityGroupRecord] = client
                .from("community_groups")
                .select()
                .ilike("location_name", pattern: pattern)
                .limit(20)
                .execute()
                .value

            async let summaryRows: [CommunityGroupRecord] = client
                .from("community_groups")
                .select()
                .ilike("summary", pattern: pattern)
                .limit(20)
                .execute()
                .value

            let (names, locations, summaries) = try await (
                nameRows,
                locationRows,
                summaryRows
            )

            guard !Task.isCancelled else { return }

            var seen = Set<UUID>()
            let results = (names + locations + summaries)
                .filter { seen.insert($0.id).inserted }
                .prefix(24)
                .map { $0 }

            searchResults = results
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            searchResults = []
        }
    }

    func clearSearch() {
        searchResults = []
    }

    func refresh(force: Bool = false) async {
        guard let userID = currentUserID else {
            groups = []
            ownMemberships = []
            ownJoinRequests = []
            ownInvites = []
            notificationPreferencesByGroup = [:]
            announcementReactionsByGroup = [:]
            leaderboardByGroup = [:]
            return
        }

        if !force,
           let lastRefreshAt,
           Date().timeIntervalSince(lastRefreshAt) < 180 {
            return
        }

        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            async let groupsQuery: [CommunityGroupRecord] = client
                .from("community_groups")
                .select()
                .order("created_at", ascending: false)
                .limit(groupFetchLimit)
                .execute()
                .value

            async let membershipsQuery: [CommunityGroupMemberRecord] = client
                .from("community_group_members")
                .select()
                .eq("user_id", value: userID)
                .execute()
                .value

            async let activityQuery: [CommunityGroupActivityRecord] = client
                .from("community_group_activity")
                .select()
                .order("created_at", ascending: false)
                .limit(50)
                .execute()
                .value

            async let invitesQuery: [CommunityGroupInviteRecord] = client
                .from("community_group_invites")
                .select()
                .eq("user_id", value: userID)
                .eq("status", value: "pending")
                .order("created_at", ascending: false)
                .execute()
                .value

            async let joinRequestsQuery: [CommunityGroupJoinRequestRecord] = client
                .from("community_group_join_requests")
                .select()
                .eq("user_id", value: userID)
                .execute()
                .value

            async let notificationPreferencesQuery:
                [CommunityGroupNotificationPreferenceRecord] = client
                    .from("community_group_notification_preferences")
                    .select()
                    .eq("user_id", value: userID)
                    .execute()
                    .value

            let discoveryGroups = try await groupsQuery
            let loadedMemberships =
                try await membershipsQuery
            let loadedActivity =
                try await activityQuery
                .filter { $0.kind != "announcement" }
            let loadedInvites = try await invitesQuery
            let loadedJoinRequests =
                try await joinRequestsQuery
            let notificationPreferences =
                try await notificationPreferencesQuery

            // The paged discovery list must never hide a club the user
            // belongs to or has been invited to just because that club is
            // older than the first page.
            var requiredGroupIDs =
                Set(loadedMemberships.map(\.groupID))
            requiredGroupIDs.formUnion(
                loadedInvites.map(\.groupID)
            )
            requiredGroupIDs.formUnion(
                loadedJoinRequests.map(\.groupID)
            )

            let discoveryGroupIDs =
                Set(discoveryGroups.map(\.id))
            let missingGroupIDs =
                requiredGroupIDs.subtracting(
                    discoveryGroupIDs
                )

            let requiredGroups: [CommunityGroupRecord]
            if missingGroupIDs.isEmpty {
                requiredGroups = []
            } else {
                requiredGroups = try await client
                    .from("community_groups")
                    .select()
                    .in(
                        "id",
                        values:
                            missingGroupIDs.map(
                                \.uuidString
                            )
                    )
                    .execute()
                    .value
            }

            let loadedGroups =
                discoveryGroups + requiredGroups
                .filter {
                    !discoveryGroupIDs.contains(
                        $0.id
                    )
                }

            var neededProfileIDs: Set<UUID> = [
                userID
            ]
            neededProfileIDs.formUnion(
                loadedGroups.map(\.creatorID)
            )
            neededProfileIDs.formUnion(
                loadedActivity.compactMap(\.actorID)
            )
            neededProfileIDs.formUnion(
                loadedInvites.map(\.invitedBy)
            )

            let profiles: [SocialProfileCard]
            if neededProfileIDs.isEmpty {
                profiles = []
            } else {
                profiles = try await client
                    .from("social_profile_cards")
                    .select()
                    .in(
                        "user_id",
                        values:
                            neededProfileIDs.map(
                                \.uuidString
                            )
                    )
                    .execute()
                    .value
            }

            groups = loadedGroups
            canLoadMoreGroups =
                discoveryGroups.count >= groupFetchLimit
            lastRefreshAt = Date()
            ownMemberships = loadedMemberships
            communityActivity = loadedActivity
            ownInvites = loadedInvites
            ownJoinRequests = loadedJoinRequests

            notificationPreferencesByGroup = Dictionary(
                uniqueKeysWithValues:
                    notificationPreferences.map {
                        ($0.groupID, $0)
                    }
            )

            profileCardsByID = Dictionary(
                uniqueKeysWithValues: profiles.map {
                    ($0.userID, $0)
                }
            )
            errorMessage = nil
        } catch is CancellationError {
            // A refresh can be cancelled when the Community view
            // disappears or a new refresh supersedes the current one.
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func mergeGroupActivityIntoCommunityFeed(
        _ groupID: UUID
    ) {
        let refreshedGroupActivity =
            activityByGroup[groupID] ?? []

        let unaffected =
            communityActivity.filter {
                $0.groupID != groupID
            }

        communityActivity =
            Array(
                (unaffected + refreshedGroupActivity)
                    .sorted {
                        $0.createdAt > $1.createdAt
                    }
                    .prefix(50)
            )
    }

    func loadMoreGroups() async {
        guard canLoadMoreGroups,
              !isLoading,
              !isLoadingMoreGroups
        else {
            return
        }

        isLoadingMoreGroups = true
        groupFetchLimit += 40
        await refresh(force: true)
        isLoadingMoreGroups = false
    }

    var calendarEvents: [CommunityGroupEventRecord] {
        let joinedIDs = joinedGroupIDs
        return eventsByGroup
            .filter { joinedIDs.contains($0.key) }
            .values
            .flatMap { $0 }
            .sorted { $0.startsAt < $1.startsAt }
    }

    var calendarEventRSVPs: [CommunityGroupEventRSVPRecord] {
        let joinedIDs = joinedGroupIDs
        return eventRSVPsByGroup
            .filter { joinedIDs.contains($0.key) }
            .values
            .flatMap { $0 }
    }

    func refreshCalendarContent() async {
        guard let userID = currentUserID else {
            return
        }

        let groupIDs = Array(joinedGroupIDs)

        guard !groupIDs.isEmpty else {
            return
        }

        do {
            let values =
                groupIDs.map(\.uuidString)

            async let eventsQuery:
                [CommunityGroupEventRecord] =
                    client
                        .from(
                            "community_group_events"
                        )
                        .select()
                        .in(
                            "group_id",
                            values: values
                        )
                        .order(
                            "starts_at",
                            ascending: true
                        )
                        .limit(1_000)
                        .execute()
                        .value

            async let rsvpQuery:
                [CommunityGroupEventRSVPRecord] =
                    client
                        .from(
                            "community_group_event_rsvps"
                        )
                        .select()
                        .in(
                            "group_id",
                            values: values
                        )
                        .eq(
                            "user_id",
                            value: userID
                        )
                        .limit(1_000)
                        .execute()
                        .value

            let loadedEvents =
                try await eventsQuery
            let loadedRSVPs =
                try await rsvpQuery

            guard !Task.isCancelled else {
                return
            }

            let eventsByID =
                Dictionary(
                    grouping: loadedEvents,
                    by: \.groupID
                )
            let rsvpsByID =
                Dictionary(
                    grouping: loadedRSVPs,
                    by: \.groupID
                )

            for groupID in groupIDs {
                eventsByGroup[groupID] =
                    eventsByID[groupID] ?? []
                eventRSVPsByGroup[groupID] =
                    rsvpsByID[groupID] ?? []
            }

            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else {
                return
            }
            errorMessage =
                error.localizedDescription
        }
    }

    func loadGroupContent(_ groupID: UUID) async {
        let creatorOwnsGroup =
            groups.first {
                $0.id == groupID &&
                $0.creatorID == currentUserID
            } != nil

        guard joinedGroupIDs.contains(groupID) ||
              creatorOwnsGroup
        else {
            return
        }

        do {
            async let membersQuery: [CommunityGroupMemberRecord] = client
                .from("community_group_members")
                .select()
                .eq("group_id", value: groupID)
                .execute()
                .value

            async let messagesQuery: [CommunityGroupMessageRecord] = client
                .from("community_group_messages")
                .select()
                .eq("group_id", value: groupID)
                .order("created_at", ascending: true)
                .limit(150)
                .execute()
                .value

            async let eventsQuery: [CommunityGroupEventRecord] = client
                .from("community_group_events")
                .select()
                .eq("group_id", value: groupID)
                .order("starts_at", ascending: true)
                .limit(100)
                .execute()
                .value

            async let challengesQuery: [CommunityGroupChallengeRecord] = client
                .from("community_group_challenges")
                .select()
                .eq("group_id", value: groupID)
                .order("starts_at", ascending: false)
                .limit(100)
                .execute()
                .value

            async let announcementsQuery: [CommunityGroupAnnouncementRecord] = client
                .from("community_group_announcements")
                .select()
                .eq("group_id", value: groupID)
                .order("created_at", ascending: false)
                .limit(30)
                .execute()
                .value

            async let activityQuery: [CommunityGroupActivityRecord] = client
                .from("community_group_activity")
                .select()
                .eq("group_id", value: groupID)
                .order("created_at", ascending: false)
                .limit(50)
                .execute()
                .value

            async let joinRequestsQuery:
                [CommunityGroupJoinRequestRecord] = client
                    .from("community_group_join_requests")
                    .select()
                    .eq("group_id", value: groupID)
                    .eq("status", value: "pending")
                    .order("created_at", ascending: true)
                    .execute()
                    .value

            async let eventRSVPsQuery:
                [CommunityGroupEventRSVPRecord] = client
                    .from("community_group_event_rsvps")
                    .select()
                    .eq("group_id", value: groupID)
                    .execute()
                    .value

            let loadedMembers = try await membersQuery
            let loadedMessages = try await messagesQuery
            let loadedEvents = try await eventsQuery
            let loadedChallenges = try await challengesQuery
            let loadedAnnouncements = try await announcementsQuery
            let loadedActivity = try await activityQuery
            let loadedJoinRequests = try await joinRequestsQuery
            let loadedEventRSVPs = try await eventRSVPsQuery

            var neededProfileIDs: Set<UUID> = []
            neededProfileIDs.formUnion(
                loadedMembers.map(\.userID)
            )
            neededProfileIDs.formUnion(
                loadedMessages.map(\.senderID)
            )
            neededProfileIDs.formUnion(
                loadedEvents.map(\.creatorID)
            )
            neededProfileIDs.formUnion(
                loadedAnnouncements.map(\.authorID)
            )
            neededProfileIDs.formUnion(
                loadedActivity.compactMap(\.actorID)
            )
            neededProfileIDs.formUnion(
                loadedJoinRequests.map(\.userID)
            )
            neededProfileIDs.formUnion(
                loadedJoinRequests.compactMap(
                    \.respondedBy
                )
            )
            if let currentUserID {
                neededProfileIDs.insert(
                    currentUserID
                )
            }

            let loadedProfiles: [SocialProfileCard]
            if neededProfileIDs.isEmpty {
                loadedProfiles = []
            } else {
                loadedProfiles = try await client
                    .from("social_profile_cards")
                    .select()
                    .in(
                        "user_id",
                        values:
                            neededProfileIDs.map(
                                \.uuidString
                            )
                    )
                    .execute()
                    .value
            }

            membersByGroup[groupID] = loadedMembers
            messagesByGroup[groupID] = loadedMessages
            eventsByGroup[groupID] = loadedEvents
            challengesByGroup[groupID] = loadedChallenges
            announcementsByGroup[groupID] = loadedAnnouncements
            activityByGroup[groupID] = loadedActivity
                .filter { $0.kind != "announcement" }
            joinRequestsByGroup[groupID] = loadedJoinRequests
            eventRSVPsByGroup[groupID] = loadedEventRSVPs

            for profile in loadedProfiles {
                profileCardsByID[profile.userID] = profile
            }

            let allContributions: [CommunityGroupChallengeWorkoutRecord] =
                try await client
                    .from("community_group_challenge_workouts")
                    .select()
                    .order("created_at", ascending: false)
                    .limit(1_000)
                    .execute()
                    .value

            let challengeIDs = Set(loadedChallenges.map(\.id))
            challengeWorkouts.removeAll {
                challengeIDs.contains($0.challengeID)
            }
            challengeWorkouts.append(
                contentsOf: allContributions.filter {
                    challengeIDs.contains($0.challengeID)
                }
            )

            await refreshAnnouncementReactions(
                groupID,
                reportErrors: false
            )
            await refreshLeaderboard(
                groupID,
                reportErrors: false
            )
            await refreshAnnouncementComments(
                groupID,
                reportErrors: false
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createGroup(
        name: String,
        summary: String,
        locationName: String = "",
        visibility: String,
        joinMode: String = "open",
        membersCanCreateContent: Bool = true,
        imageJPEGData: Data? = nil,
        headerImageJPEGData: Data? = nil,
        headerArtworkReference: String? = nil
    ) async -> Bool {
        guard let userID = currentUserID else { return false }

        let cleanName = name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let cleanLocation = locationName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard cleanName.count >= 2 else {
            errorMessage = "Add a group name."
            return false
        }

        do {
            let resolvedVisibility =
                visibility == "private"
                    ? "private"
                    : "public"
            let resolvedJoinMode =
                resolvedVisibility == "private" &&
                joinMode == "open"
                    ? "invite_only"
                    : (
                        ["open", "approval", "invite_only"]
                            .contains(joinMode)
                            ? joinMode
                            : "open"
                    )

            let groupID = UUID()

            let payload = CommunityGroupInsert(
                id: groupID,
                creatorID: userID,
                name: String(cleanName.prefix(80)),
                summary: String(summary.prefix(800)),
                locationName:
                    String(cleanLocation.prefix(120)),
                visibility: resolvedVisibility,
                joinMode: resolvedJoinMode,
                membersCanCreateContent:
                    membersCanCreateContent
            )

            try await client
                .from("community_groups")
                .insert(payload)
                .execute()

            let ownerMembership =
                CommunityGroupMemberRecord(
                    groupID: groupID,
                    userID: userID,
                    role: "owner",
                    joinedAt: Date()
                )

            ownMemberships.removeAll {
                $0.groupID == groupID &&
                $0.userID == userID
            }
            ownMemberships.append(ownerMembership)
            membersByGroup[groupID] = [ownerMembership]

            if let imageJPEGData {
                guard imageJPEGData.count <= 5_242_880 else {
                    errorMessage =
                        "Club image must be smaller than 5 MB."
                    await refresh(force: true)
                    return true
                }

                do {
                    let published =
                        try await ATHLTHPublicImagePublisher
                            .publish(
                                jpegData:
                                    imageJPEGData,
                                purpose:
                                    .clubCover,
                                groupID:
                                    groupID,
                                client: client
                            )

                    try await client
                        .from("community_groups")
                        .update(
                            CommunityGroupImageUpdate(
                                imageURL:
                                    published.url.absoluteString,
                                updatedAt: Date()
                            )
                        )
                        .eq("id", value: groupID)
                        .execute()
                } catch {
                    // The club itself has already been created. Keep it
                    // usable even if Storage is temporarily unavailable;
                    // the owner can add/change the cover in Club Settings.
                    errorMessage =
                        "Club created, but the image could not be uploaded. You can add it from Club Settings."
                }
            }

            if let headerImageJPEGData {
                if headerImageJPEGData.count <=
                    5_242_880 {
                    do {
                        let published =
                            try await ATHLTHPublicImagePublisher
                                .publish(
                                    jpegData:
                                        headerImageJPEGData,
                                    purpose:
                                        .clubHeader,
                                    groupID:
                                        groupID,
                                    client: client
                                )

                        try await client
                            .from(
                                "community_groups"
                            )
                            .update(
                                CommunityGroupHeaderImageUpdate(
                                    headerImageURL:
                                        published.url
                                            .absoluteString,
                                    updatedAt:
                                        Date()
                                )
                            )
                            .eq(
                                "id",
                                value:
                                    groupID
                            )
                            .execute()
                    } catch {
                        errorMessage =
                            "Club created, but the header image could not be uploaded. You can change it from Club Settings."
                    }
                }
            } else if let headerArtworkReference,
                      ATHLTHStandardArtwork(
                        reference:
                            headerArtworkReference
                      ) != nil {
                do {
                    try await client
                        .from(
                            "community_groups"
                        )
                        .update(
                            CommunityGroupHeaderImageUpdate(
                                headerImageURL:
                                    headerArtworkReference,
                                updatedAt:
                                    Date()
                            )
                        )
                        .eq(
                            "id",
                            value:
                                groupID
                        )
                        .execute()
                } catch {
                    errorMessage =
                        "Club created, but the header image could not be saved. You can change it from Club Settings."
                }
            }

            await refresh(force: true)

            // A refresh may finish before the detail membership cache is
            // populated. Keep the owner visible and then hydrate the full
            // Club content immediately.
            if !ownMemberships.contains(
                where: {
                    $0.groupID == groupID &&
                    $0.userID == userID
                }
            ) {
                ownMemberships.append(ownerMembership)
            }

            if membersByGroup[groupID]?.contains(
                where: { $0.userID == userID }
            ) != true {
                membersByGroup[groupID, default: []]
                    .insert(ownerMembership, at: 0)
            }

            await loadGroupContent(groupID)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func updateGroup(
        _ group: CommunityGroupRecord,
        name: String,
        locationName: String,
        summary: String,
        visibility: String,
        joinMode: String? = nil,
        membersCanCreateContent: Bool? = nil,
        themeKey: String? = nil
    ) async -> Bool {
        guard canManage(group) else {
            return false
        }

        let cleanName = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLocation = locationName
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard cleanName.count >= 2 else {
            errorMessage = "Add a group name."
            return false
        }

        do {
            let resolvedVisibility =
                visibility == "private"
                    ? "private"
                    : "public"
            let requestedJoinMode =
                joinMode ?? group.joinMode
            let resolvedJoinMode =
                resolvedVisibility == "private" &&
                requestedJoinMode == "open"
                    ? "invite_only"
                    : requestedJoinMode

            let payload = CommunityGroupUpdate(
                name: String(cleanName.prefix(80)),
                summary: String(summary.prefix(800)),
                locationName: String(cleanLocation.prefix(120)),
                visibility: resolvedVisibility,
                joinMode: resolvedJoinMode,
                membersCanCreateContent:
                    membersCanCreateContent ??
                    group.membersCanCreateContent,
                themeKey:
                    CommunityClubTheme(
                        rawValue: themeKey ?? group.themeKey ?? ""
                    )?.rawValue ??
                    CommunityClubTheme.emerald.rawValue,
                updatedAt: Date()
            )

            try await client
                .from("community_groups")
                .update(payload)
                .eq("id", value: group.id)
                .execute()

            await refresh(force: true)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func uploadGroupImage(
        _ group: CommunityGroupRecord,
        jpegData: Data
    ) async -> Bool {
        guard canManage(group) else {
            return false
        }

        guard jpegData.count <= 5_242_880 else {
            errorMessage = "Club image must be smaller than 5 MB."
            return false
        }

        do {
            let published =
                try await ATHLTHPublicImagePublisher
                    .publish(
                        jpegData: jpegData,
                        purpose:
                            .clubCover,
                        groupID:
                            group.id,
                        client: client
                    )

            try await client
                .from("community_groups")
                .update(
                    CommunityGroupImageUpdate(
                        imageURL:
                            published.url.absoluteString,
                        updatedAt: Date()
                    )
                )
                .eq("id", value: group.id)
                .execute()

            await refresh(force: true)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func removeGroupImage(
        _ group: CommunityGroupRecord
    ) async -> Bool {
        guard canManage(group) else {
            return false
        }

        let path = "\(group.id.uuidString.lowercased())/cover.jpg"

        do {
            _ = try? await client.storage
                .from("community-group-images")
                .remove(paths: [path])

            try await client
                .from("community_groups")
                .update(
                    CommunityGroupImageUpdate(
                        imageURL: nil,
                        updatedAt: Date()
                    )
                )
                .eq("id", value: group.id)
                .execute()

            await refresh(force: true)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func uploadGroupHeaderImage(
        _ group: CommunityGroupRecord,
        jpegData: Data
    ) async -> Bool {
        guard canManage(group) else {
            return false
        }

        guard jpegData.count <= 5_242_880 else {
            errorMessage = "Club header image must be smaller than 5 MB."
            return false
        }

        do {
            let published =
                try await ATHLTHPublicImagePublisher
                    .publish(
                        jpegData: jpegData,
                        purpose:
                            .clubHeader,
                        groupID:
                            group.id,
                        client: client
                    )

            try await client
                .from("community_groups")
                .update(
                    CommunityGroupHeaderImageUpdate(
                        headerImageURL:
                            published.url.absoluteString,
                        updatedAt: Date()
                    )
                )
                .eq("id", value: group.id)
                .execute()

            await refresh(force: true)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func setGroupHeaderArtwork(
        _ group: CommunityGroupRecord,
        artwork: ATHLTHStandardArtwork
    ) async -> Bool {
        guard canManage(group) else {
            return false
        }

        let path =
            "\(group.id.uuidString.lowercased())/header.jpg"

        do {
            _ = try? await client.storage
                .from("community-group-images")
                .remove(paths: [path])

            try await client
                .from("community_groups")
                .update(
                    CommunityGroupHeaderImageUpdate(
                        headerImageURL:
                            artwork.reference,
                        updatedAt: Date()
                    )
                )
                .eq("id", value: group.id)
                .execute()

            errorMessage = nil
            await refresh(force: true)
            return true
        } catch {
            errorMessage =
                error.localizedDescription
            return false
        }
    }

    func removeGroupHeaderImage(
        _ group: CommunityGroupRecord
    ) async -> Bool {
        guard canManage(group) else {
            return false
        }

        let path =
            "\(group.id.uuidString.lowercased())/header.jpg"

        do {
            _ = try? await client.storage
                .from("community-group-images")
                .remove(paths: [path])

            try await client
                .from("community_groups")
                .update(
                    CommunityGroupHeaderImageUpdate(
                        headerImageURL: nil,
                        updatedAt: Date()
                    )
                )
                .eq("id", value: group.id)
                .execute()

            await refresh(force: true)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func setFeaturedChallenge(
        _ challengeID: UUID?,
        in group: CommunityGroupRecord
    ) async -> Bool {
        guard canManage(group) else {
            return false
        }

        if let challengeID,
           !challenges(in: group.id).contains(
                where: { $0.id == challengeID }
           ) {
            errorMessage =
                "That challenge does not belong to this Club."
            return false
        }

        do {
            try await client
                .from("community_groups")
                .update(
                    CommunityGroupFeaturedChallengeUpdate(
                        featuredChallengeID: challengeID,
                        updatedAt: Date()
                    )
                )
                .eq("id", value: group.id)
                .execute()

            await refresh(force: true)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteGroup(
        _ group: CommunityGroupRecord
    ) async -> Bool {
        guard isOwner(of: group) else {
            errorMessage = "Only the group owner can delete this group."
            return false
        }

        let imagePaths = [
            "\(group.id.uuidString.lowercased())/cover.jpg",
            "\(group.id.uuidString.lowercased())/header.jpg"
        ]

        do {
            // Storage objects do not cascade with the database row, so remove
            // both visual assets while manager permissions can still be checked.
            _ = try? await client.storage
                .from("community-group-images")
                .remove(paths: imagePaths)

            try await client
                .from("community_groups")
                .delete()
                .eq("id", value: group.id)
                .execute()

            membersByGroup[group.id] = nil
            announcementsByGroup[group.id] = nil
            announcementReactionsByGroup[group.id] = nil
            announcementCommentsByGroup[group.id] = nil
            leaderboardByGroup[group.id] = nil
            activityByGroup[group.id] = nil
            messagesByGroup[group.id] = nil
            eventsByGroup[group.id] = nil
            challengesByGroup[group.id] = nil

            await refresh(force: true)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func postAnnouncement(
        groupID: UUID,
        body: String
    ) async -> Bool {
        guard let userID = currentUserID,
              let group = group(for: groupID),
              canPublishUpdates(group)
        else {
            return false
        }

        let clean = body.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !clean.isEmpty else {
            return false
        }

        do {
            try await client
                .from("community_group_announcements")
                .insert(
                    CommunityGroupAnnouncementInsert(
                        groupID: groupID,
                        authorID: userID,
                        body: String(clean.prefix(1200))
                    )
                )
                .execute()

            // The announcement only changes detail-scoped group content.
            // Avoid a full Community reload (groups, memberships, activity,
            // invites and profiles) for a local timeline mutation.
            await loadGroupContent(groupID)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func toggleAnnouncementLike(
        groupID: UUID,
        announcementID: UUID
    ) async -> Bool {
        guard let userID = currentUserID,
              joinedGroupIDs.contains(groupID) ||
                groups.first(where: {
                    $0.id == groupID &&
                    $0.creatorID == userID
                }) != nil
        else {
            return false
        }

        do {
            if hasLikedAnnouncement(
                announcementID,
                in: groupID
            ) {
                try await client
                    .from(
                        "community_group_announcement_reactions"
                    )
                    .delete()
                    .eq(
                        "announcement_id",
                        value: announcementID
                    )
                    .eq("user_id", value: userID)
                    .eq("reaction", value: "like")
                    .execute()
            } else {
                try await client
                    .from(
                        "community_group_announcement_reactions"
                    )
                    .insert(
                        CommunityGroupAnnouncementReactionInsert(
                            announcementID: announcementID,
                            groupID: groupID,
                            userID: userID,
                            reaction: "like"
                        )
                    )
                    .execute()
            }

            await refreshAnnouncementReactions(groupID)
            await refreshLeaderboard(groupID)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func refreshAnnouncementReactions(
        _ groupID: UUID,
        reportErrors: Bool = true
    ) async {
        do {
            let rows:
                [CommunityGroupAnnouncementReactionRecord] =
                    try await client
                        .from(
                            "community_group_announcement_reactions"
                        )
                        .select()
                        .eq("group_id", value: groupID)
                        .order(
                            "created_at",
                            ascending: false
                        )
                        .limit(1_000)
                        .execute()
                        .value

            announcementReactionsByGroup[groupID] = rows
        } catch {
            if reportErrors {
                errorMessage = error.localizedDescription
            }
        }
    }

    func refreshAnnouncementComments(
        _ groupID: UUID,
        reportErrors: Bool = true
    ) async {
        do {
            let rows: [CommunityGroupContentCommentRecord] =
                try await client
                    .from("community_group_content_comments")
                    .select()
                    .eq("group_id", value: groupID)
                    .eq("content_type", value: "announcement")
                    .order("created_at", ascending: true)
                    .limit(500)
                    .execute()
                    .value

            announcementCommentsByGroup[groupID] = rows
        } catch {
            if reportErrors {
                errorMessage = error.localizedDescription
            }
        }
    }

    func postAnnouncementComment(
        groupID: UUID,
        announcementID: UUID,
        body: String
    ) async -> Bool {
        guard let userID = currentUserID,
              joinedGroupIDs.contains(groupID) ||
                groups.first(where: {
                    $0.id == groupID &&
                    $0.creatorID == userID
                }) != nil
        else {
            return false
        }

        let clean = body.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !clean.isEmpty else {
            return false
        }

        do {
            try await client
                .from("community_group_content_comments")
                .insert(
                    CommunityGroupContentCommentInsert(
                        groupID: groupID,
                        contentType: "announcement",
                        contentID: announcementID,
                        authorID: userID,
                        body: String(clean.prefix(1200))
                    )
                )
                .execute()

            await refreshAnnouncementComments(groupID)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteAnnouncementComment(
        groupID: UUID,
        commentID: UUID
    ) async -> Bool {
        guard currentUserID != nil else {
            return false
        }

        do {
            try await client
                .from("community_group_content_comments")
                .delete()
                .eq("id", value: commentID)
                .eq("group_id", value: groupID)
                .eq("content_type", value: "announcement")
                .execute()

            await refreshAnnouncementComments(groupID)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func refreshLeaderboard(
        _ groupID: UUID,
        reportErrors: Bool = true
    ) async {
        do {
            let rows: [CommunityGroupEngagementLeaderboardEntry] =
                try await client
                    .rpc(
                        "get_community_group_leaderboard",
                        params:
                            CommunityGroupLeaderboardParams(
                                groupID: groupID
                            )
                    )
                    .execute()
                    .value

            leaderboardByGroup[groupID] = rows
        } catch {
            if reportErrors {
                errorMessage = error.localizedDescription
            }
        }
    }

    func deleteAnnouncement(
        groupID: UUID,
        announcementID: UUID
    ) async -> Bool {
        guard let group = group(for: groupID),
              canManage(group)
        else {
            return false
        }

        do {
            try await client
                .from("community_group_announcements")
                .delete()
                .eq("id", value: announcementID)
                .eq("group_id", value: groupID)
                .execute()

            await loadGroupContent(groupID)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func pinAnnouncement(
        groupID: UUID,
        announcementID: UUID?
    ) async -> Bool {
        guard let group = group(for: groupID),
              canPublishUpdates(group)
        else {
            return false
        }

        do {
            try await client
                .rpc(
                    "set_community_group_announcement_pin",
                    params:
                        CommunityGroupAnnouncementPinParams(
                            groupID: groupID,
                            announcementID: announcementID
                        )
                )
                .execute()

            await loadGroupContent(groupID)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func requestJoin(
        _ group: CommunityGroupRecord
    ) async -> String {
        guard currentUserID != nil else {
            return "unavailable"
        }

        do {
            let result: String = try await client
                .rpc(
                    "request_community_group_join",
                    params: CommunityGroupJoinParams(
                        groupID: group.id
                    )
                )
                .execute()
                .value

            await refresh(force: true)

            if result == "joined" {
                await loadGroupContent(group.id)
            }

            return result
        } catch {
            errorMessage = error.localizedDescription
            return "error"
        }
    }

    func respondToJoinRequest(
        groupID: UUID,
        userID: UUID,
        accept: Bool
    ) async -> Bool {
        guard let group = group(for: groupID),
              canManage(group)
        else {
            return false
        }

        do {
            try await client
                .rpc(
                    "respond_community_group_join_request",
                    params: CommunityGroupJoinResponseParams(
                        groupID: groupID,
                        userID: userID,
                        accept: accept
                    )
                )
                .execute()

            await refresh(force: true)
            await loadGroupContent(groupID)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func inviteMember(
        groupID: UUID,
        userID: UUID
    ) async -> Bool {
        guard let group = group(for: groupID),
              canManage(group)
        else {
            return false
        }

        do {
            try await client
                .rpc(
                    "invite_community_group_member",
                    params: CommunityGroupInviteParams(
                        groupID: groupID,
                        userID: userID
                    )
                )
                .execute()

            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func respondToInvite(
        groupID: UUID,
        accept: Bool
    ) async -> Bool {
        do {
            try await client
                .rpc(
                    "respond_community_group_invite",
                    params: CommunityGroupInviteResponseParams(
                        groupID: groupID,
                        accept: accept
                    )
                )
                .execute()

            await refresh(force: true)

            if accept {
                await loadGroupContent(groupID)
            }

            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func setGroupNotificationMode(
        groupID: UUID,
        mode: String
    ) async -> Bool {
        guard let userID = currentUserID,
              joinedGroupIDs.contains(groupID),
              ["all", "muted"].contains(mode)
        else {
            return false
        }

        let record =
            CommunityGroupNotificationPreferenceRecord(
                groupID: groupID,
                userID: userID,
                mode: mode,
                updatedAt: Date()
            )

        do {
            try await client
                .from("community_group_notification_preferences")
                .upsert(
                    record,
                    onConflict: "group_id,user_id"
                )
                .execute()

            notificationPreferencesByGroup[groupID] =
                record
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func setEventRSVP(
        groupID: UUID,
        eventID: UUID,
        status: String
    ) async -> Bool {
        guard let userID = currentUserID,
              joinedGroupIDs.contains(groupID),
              ["going", "maybe", "not_going"]
                .contains(status)
        else {
            return false
        }

        let record = CommunityGroupEventRSVPRecord(
            groupID: groupID,
            eventID: eventID,
            userID: userID,
            status: status,
            updatedAt: Date()
        )

        do {
            try await client
                .from("community_group_event_rsvps")
                .upsert(
                    record,
                    onConflict: "event_id,user_id"
                )
                .execute()

            await loadGroupContent(groupID)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func removeMember(
        groupID: UUID,
        userID: UUID
    ) async -> Bool {
        guard let group = group(for: groupID),
              canManage(group),
              userID != group.creatorID
        else {
            return false
        }

        do {
            try await client
                .from("community_group_members")
                .delete()
                .eq("group_id", value: groupID)
                .eq("user_id", value: userID)
                .neq("role", value: "owner")
                .execute()

            await refresh(force: true)
            await loadGroupContent(groupID)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func setMemberRole(
        groupID: UUID,
        userID: UUID,
        role: String
    ) async -> Bool {
        guard let group = group(for: groupID),
              canManage(group),
              userID != group.creatorID,
              ["admin", "contributor", "member"].contains(role)
        else {
            return false
        }

        do {
            try await client
                .from("community_group_members")
                .update(["role": role])
                .eq("group_id", value: groupID)
                .eq("user_id", value: userID)
                .execute()

            await loadGroupContent(groupID)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func join(_ group: CommunityGroupRecord) async {
        _ = await requestJoin(group)
    }

    func leave(_ group: CommunityGroupRecord) async {
        guard let userID = currentUserID,
              !isOwner(of: group)
        else { return }

        do {
            try await client
                .from("community_group_members")
                .delete()
                .eq("group_id", value: group.id)
                .eq("user_id", value: userID)
                .execute()

            await refresh(force: true)
            membersByGroup[group.id] = nil
            announcementsByGroup[group.id] = nil
            announcementReactionsByGroup[group.id] = nil
            announcementCommentsByGroup[group.id] = nil
            leaderboardByGroup[group.id] = nil
            activityByGroup[group.id] = nil
            messagesByGroup[group.id] = nil
            eventsByGroup[group.id] = nil
            challengesByGroup[group.id] = nil
            joinRequestsByGroup[group.id] = nil
            eventRSVPsByGroup[group.id] = nil
            notificationPreferencesByGroup[group.id] = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sendMessage(
        groupID: UUID,
        senderName: String,
        body: String,
        imageJPEGData: Data? = nil
    ) async -> Bool {
        guard let userID = currentUserID else {
            return false
        }

        let clean = body.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !clean.isEmpty || imageJPEGData != nil else {
            return false
        }

        do {
            let messageID = UUID()
            let imageURL: String?

            if let imageJPEGData {
                let published =
                    try await ATHLTHPublicImagePublisher
                        .publish(
                            jpegData: imageJPEGData,
                            purpose: .clubChatMessage,
                            entityID: messageID,
                            groupID: groupID,
                            client: client
                        )
                imageURL = published.url.absoluteString
            } else {
                imageURL = nil
            }

            try await client
                .from("community_group_messages")
                .insert(
                    CommunityGroupMessageInsert(
                        id: messageID,
                        groupID: groupID,
                        senderID: userID,
                        senderName: String(
                            senderName
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .prefix(100)
                        ),
                        body: String(clean.prefix(2000)),
                        imageURL: imageURL
                    )
                )
                .execute()

            await refreshMessages(groupID)
            await refreshLeaderboard(groupID)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func refreshMessages(_ groupID: UUID) async {
        guard joinedGroupIDs.contains(groupID) else { return }

        do {
            let rows: [CommunityGroupMessageRecord] = try await client
                .from("community_group_messages")
                .select()
                .eq("group_id", value: groupID)
                .order("created_at", ascending: true)
                .limit(150)
                .execute()
                .value

            messagesByGroup[groupID] = rows
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func communityContentImagePath(
        groupID: UUID,
        kind: String,
        contentID: UUID
    ) -> String {
        "\(groupID.uuidString.lowercased())/" +
        "\(kind)/" +
        "\(contentID.uuidString.lowercased())/cover.jpg"
    }

    private func uploadCommunityContentImage(
        groupID: UUID,
        kind: String,
        contentID: UUID,
        jpegData: Data
    ) async throws -> String {
        guard jpegData.count <= 5_242_880 else {
            throw NSError(
                domain: "ATHLTH.Community",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Image must be smaller than 5 MB."
                ]
            )
        }

        let published =
            try await ATHLTHPublicImagePublisher
                .publish(
                    jpegData: jpegData,
                    purpose:
                        .clubContent,
                    entityID:
                        contentID,
                    groupID:
                        groupID,
                    contentKind:
                        kind,
                    client: client
                )

        return published.url.absoluteString
    }

    private func removeCommunityContentImage(
        groupID: UUID,
        kind: String,
        contentID: UUID
    ) async {
        let path = communityContentImagePath(
            groupID: groupID,
            kind: kind,
            contentID: contentID
        )

        _ = try? await client.storage
            .from("community-content-images")
            .remove(paths: [path])
    }

    private func saveContentHosts(
        groupID: UUID,
        contentType: String,
        contentID: UUID,
        cohostIDs: [UUID]
    ) async throws {
        let unique = Array(Set(cohostIDs))
        guard !unique.isEmpty else {
            return
        }

        let payload = unique.map {
            CommunityGroupContentHostInsert(
                groupID: groupID,
                contentType: contentType,
                contentID: contentID,
                userID: $0
            )
        }

        try await client
            .from("community_group_content_hosts")
            .insert(payload)
            .execute()
    }

    func createEvent(
        groupID: UUID,
        title: String,
        summary: String,
        activityType: String,
        startsAt: Date,
        meetingName: String,
        imageData: Data? = nil,
        imageReference: String? = nil,
        activityConfiguration:
            CommunityGroupActivityConfiguration? = nil,
        advancedOptions:
            CommunityGroupEventAdvancedOptions =
                CommunityGroupEventAdvancedOptions(),
        cohostIDs: [UUID] = []
    ) async -> Bool {
        guard currentUserID != nil,
              let group = group(for: groupID),
              canCreateGroupContent(group)
        else {
            errorMessage =
                "You do not have permission to create group events."
            return false
        }

        let cleanTitle = title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let cleanMeet = meetingName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !cleanTitle.isEmpty else {
            errorMessage = "Add an event title."
            return false
        }

        let eventID = UUID()
        var uploadedImage = false

        do {
            let imageURL: String?
            if let imageData {
                imageURL = try await uploadCommunityContentImage(
                    groupID: groupID,
                    kind: "events",
                    contentID: eventID,
                    jpegData: imageData
                )
                uploadedImage = true
            } else {
                imageURL = imageReference
            }

            try await client
                .rpc(
                    "create_community_group_event_v2",
                    params:
                        CommunityGroupEventCreateV2Params(
                            id: eventID,
                            groupID: groupID,
                            title: String(
                                cleanTitle.prefix(160)
                            ),
                            summary: String(
                                summary.prefix(1200)
                            ),
                            activityType: activityType,
                            startsAt: startsAt,
                            meetingName: String(
                                cleanMeet.prefix(180)
                            ),
                            imageURL: imageURL,
                            activityConfiguration:
                                activityConfiguration,
                            options: advancedOptions
                        )
                )
                .execute()

            try await saveContentHosts(
                groupID: groupID,
                contentType: "event",
                contentID: eventID,
                cohostIDs: cohostIDs
            )

            errorMessage = nil
            await loadGroupContent(groupID)
            mergeGroupActivityIntoCommunityFeed(
                groupID
            )
            return true
        } catch {
            if uploadedImage {
                await removeCommunityContentImage(
                    groupID: groupID,
                    kind: "events",
                    contentID: eventID
                )
            }

            errorMessage = error.localizedDescription
            return false
        }
    }

    func createChallenge(
        groupID: UUID,
        title: String,
        summary: String,
        metric: CommunityGroupChallengeMetric,
        targetValue: Double,
        startsAt: Date,
        endsAt: Date,
        imageData: Data? = nil,
        imageReference: String? = nil,
        activityConfiguration:
            CommunityGroupActivityConfiguration? = nil,
        advancedOptions:
            CommunityGroupChallengeAdvancedOptions =
                CommunityGroupChallengeAdvancedOptions(),
        cohostIDs: [UUID] = []
    ) async -> Bool {
        guard currentUserID != nil,
              let group = group(for: groupID),
              canCreateGroupContent(group),
              targetValue > 0,
              endsAt > startsAt
        else {
            errorMessage =
                "Check the challenge details and your group permissions."
            return false
        }

        let cleanTitle = title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !cleanTitle.isEmpty else {
            errorMessage = "Give the challenge a title."
            return false
        }

        let challengeID = UUID()
        var uploadedImage = false

        do {
            let imageURL: String?
            if let imageData {
                imageURL = try await uploadCommunityContentImage(
                    groupID: groupID,
                    kind: "challenges",
                    contentID: challengeID,
                    jpegData: imageData
                )
                uploadedImage = true
            } else {
                imageURL = imageReference
            }

            try await client
                .rpc(
                    "create_community_group_challenge_v2",
                    params:
                        CommunityGroupChallengeCreateV2Params(
                            id: challengeID,
                            groupID: groupID,
                            title: String(
                                cleanTitle.prefix(160)
                            ),
                            summary: String(
                                summary.prefix(800)
                            ),
                            metric: metric.rawValue,
                            targetValue: targetValue,
                            startsAt: startsAt,
                            endsAt: endsAt,
                            imageURL: imageURL,
                            activityConfiguration:
                                activityConfiguration,
                            options: advancedOptions
                        )
                )
                .execute()

            try await saveContentHosts(
                groupID: groupID,
                contentType: "challenge",
                contentID: challengeID,
                cohostIDs: cohostIDs
            )

            errorMessage = nil
            await loadGroupContent(groupID)
            mergeGroupActivityIntoCommunityFeed(
                groupID
            )
            return true
        } catch {
            if uploadedImage {
                await removeCommunityContentImage(
                    groupID: groupID,
                    kind: "challenges",
                    contentID: challengeID
                )
            }

            errorMessage = error.localizedDescription
            return false
        }
    }

    private func challengeMatchesWorkout(
        _ challenge: CommunityGroupChallengeRecord,
        workout: SocialPublishableWorkout
    ) -> Bool {
        guard let configuration =
            challenge.activityConfiguration
        else {
            return true
        }

        switch configuration.activityType {
        case "running":
            return workout.activity == .running
        case "walking":
            return workout.activity == .walking
        case "cycling":
            return workout.activity == .cycling
        case "strength":
            return workout.activity == .strength
        default:
            return true
        }
    }

    func recordCompletedWorkout(
        _ workout: SocialPublishableWorkout
    ) async {
        guard let userID = currentUserID,
              !joinedGroupIDs.isEmpty
        else {
            return
        }

        do {
            do {
                try await client
                    .rpc(
                        "record_community_group_workout",
                        params:
                            CommunityGroupWorkoutActivityParams(
                                workoutID: workout.id,
                                completedAt: workout.endDate
                            )
                    )
                    .execute()
            } catch {
                // Club leaderboard tracking is additive and must never
                // block existing challenge workout processing.
            }

            let activeChallenges: [CommunityGroupChallengeRecord] =
                try await client
                    .from("community_group_challenges")
                    .select()
                    .lte(
                        "starts_at",
                        value: workout.endDate
                    )
                    .gte(
                        "ends_at",
                        value: workout.startDate
                    )
                    .neq("status", value: "cancelled")
                    .execute()
                    .value

            guard !activeChallenges.isEmpty else {
                return
            }

            let participations:
                [CommunityGroupChallengeParticipantRecord] =
                    try await client
                        .from(
                            "community_group_challenge_participants"
                        )
                        .select()
                        .eq("user_id", value: userID)
                        .execute()
                        .value

            let joinedChallengeIDs = Set(
                participations
                    .filter { $0.status == "joined" }
                    .map(\.challengeID)
            )

            let existingAttempts:
                [CommunityGroupChallengeWorkoutRecord] =
                    try await client
                        .from(
                            "community_group_challenge_workouts"
                        )
                        .select()
                        .eq("user_id", value: userID)
                        .execute()
                        .value

            var writes:
                [CommunityGroupChallengeWorkoutInsert] = []

            for challenge in activeChallenges {
                guard challengeMatchesWorkout(
                    challenge,
                    workout: workout
                ) else {
                    continue
                }

                if challenge.joinRequired &&
                    !joinedChallengeIDs.contains(
                        challenge.id
                    ) {
                    continue
                }

                if let limit = challenge.attemptLimit {
                    let attemptCount =
                        existingAttempts.filter {
                            $0.challengeID ==
                                challenge.id
                        }.count

                    if attemptCount >= limit {
                        continue
                    }
                }

                var contribution: Double

                switch challenge.metric {
                case .distanceKM:
                    contribution =
                        (workout.distanceMeters ?? 0) /
                        1_000

                case .workouts:
                    contribution = 1

                case .activeMinutes:
                    contribution = max(
                        workout.duration / 60,
                        0
                    )

                case .fastestTime:
                    let targetMeters =
                        challenge
                            .activityConfiguration?
                            .distanceKilometers
                            .map { $0 * 1_000 }

                    if let targetMeters,
                       let verifiedDuration =
                        await HealthKitManager.shared
                            .groupChallengeFastestSegmentDuration(
                                workoutID: workout.id,
                                targetDistanceMeters:
                                    targetMeters
                            ) {
                        contribution = verifiedDuration
                    } else if let targetMeters,
                              (workout.distanceMeters ?? 0) >=
                                targetMeters {
                        contribution = workout.duration
                    } else if targetMeters == nil {
                        contribution = workout.duration
                    } else {
                        continue
                    }
               

                case .strengthVolume:
                    contribution =
                        workout
                            .strengthTotalVolumeKilograms
                            ?? 0

                case .heaviestWeight:
                    contribution =
                        workout
                            .strengthHeaviestWeightKilograms
                            ?? 0

                case .strengthReps:
                    contribution =
                        Double(
                            workout.strengthTotalReps
                            ?? 0
                        )
                }

                guard contribution > 0 else {
                    continue
                }

                var routeMatch: Double?
                var verificationStatus =
                    "not_required"

                if challenge
                    .routeVerificationEnabled {
                    guard let route =
                        challenge
                            .activityConfiguration?
                            .route
                    else {
                        verificationStatus =
                            "unverified"
                        writes.append(
                            CommunityGroupChallengeWorkoutInsert(
                                challengeID:
                                    challenge.id,
                                userID: userID,
                                workoutID: workout.id,
                                contribution:
                                    contribution,
                                routeMatchPercent: nil,
                                verificationStatus:
                                    verificationStatus
                            )
                        )
                        continue
                    }

                    routeMatch =
                        await HealthKitManager.shared
                            .groupChallengeRouteMatchPercent(
                                workoutID: workout.id,
                                referenceCoordinates:
                                    route.coordinates,
                                toleranceMeters:
                                    Double(
                                        challenge
                                            .routeToleranceMeters
                                    )
                            )

                    verificationStatus =
                        (routeMatch ?? 0) >= 90
                            ? "verified"
                            : "unverified"
                }

                writes.append(
                    CommunityGroupChallengeWorkoutInsert(
                        challengeID: challenge.id,
                        userID: userID,
                        workoutID: workout.id,
                        contribution: contribution,
                        routeMatchPercent:
                            routeMatch,
                        verificationStatus:
                            verificationStatus
                    )
                )
            }

            guard !writes.isEmpty else {
                return
            }

            try await client
                .from(
                    "community_group_challenge_workouts"
                )
                .upsert(
                    writes,
                    onConflict:
                        "challenge_id,user_id,workout_id"
                )
                .execute()

            for challenge in activeChallenges
            where writes.contains(
                where: {
                    $0.challengeID == challenge.id
                }
            ) {
                await loadGroupContent(
                    challenge.groupID
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum CommunityGroupsTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case chat = "Chat"
    case events = "Events"
    case challenges = "Challenges"

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .overview:
            return ATHLTHLocalization.choose(
                english: "Overview",
                norwegian: "Oversikt"
            )
        case .chat:
            return "Chat"
        case .events:
            return "Events"
        case .challenges:
            return "Challenges"
        }
    }
}

struct CommunityGroupsView: View {
    @EnvironmentObject private var groups: CommunityGroupStore

    @State private var query = ""
    @State private var showingCreate = false
    @State private var discoverFilter:
        ClubDiscoveryFilter = .all

    private var clubForest: Color {
        Color(red: 0.025, green: 0.30, blue: 0.21)
    }

    private var clubEmerald: Color {
        Color(red: 0.055, green: 0.49, blue: 0.32)
    }

    private var clubMint: Color {
        Color(red: 0.90, green: 0.96, blue: 0.92)
    }

    private var clubSage: Color {
        Color(red: 0.77, green: 0.88, blue: 0.81)
    }

    private enum ClubDiscoveryFilter:
        String,
        CaseIterable,
        Identifiable {
        case all
        case running
        case strength
        case hyrox
        case outdoors

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all:
                return ATHLTHLocalization.choose(
                    english: "All",
                    norwegian: "Alle"
                )
            case .running:
                return ATHLTHLocalization.choose(
                    english: "Running",
                    norwegian: "Løping"
                )
            case .strength:
                return ATHLTHLocalization.choose(
                    english: "Strength",
                    norwegian: "Styrke"
                )
            case .hyrox:
                return "Hyrox"
            case .outdoors:
                return ATHLTHLocalization.choose(
                    english: "Outdoors",
                    norwegian: "Tur"
                )
            }
        }

        var icon: String {
            switch self {
            case .all:
                return "sparkles"
            case .running:
                return "figure.run"
            case .strength:
                return "dumbbell.fill"
            case .hyrox:
                return "trophy.fill"
            case .outdoors:
                return "mountain.2.fill"
            }
        }

        func matches(
            _ group: CommunityGroupRecord
        ) -> Bool {
            guard self != .all else {
                return true
            }

            let searchable =
                [
                    group.name,
                    group.summary,
                    group.locationName
                ]
                .joined(separator: " ")
                .lowercased()

            switch self {
            case .all:
                return true
            case .running:
                return searchable.contains("run") ||
                    searchable.contains("løp") ||
                    searchable.contains("jogg")
            case .strength:
                return searchable.contains("strength") ||
                    searchable.contains("styrke") ||
                    searchable.contains("gym")
            case .hyrox:
                return searchable.contains("hyrox")
            case .outdoors:
                return searchable.contains("tur") ||
                    searchable.contains("hike") ||
                    searchable.contains("fjell") ||
                    searchable.contains("trail")
            }
        }
    }

    private var matchingGroups:
        [CommunityGroupRecord] {
        let publicGroups =
            groups.groups.filter {
                $0.visibility == "public" &&
                !groups.joinedGroupIDs
                    .contains($0.id) &&
                groups.pendingInvite(
                    for: $0.id
                ) == nil
            }

        let clean =
            query
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
                .lowercased()

        return publicGroups.filter {
            group in

            let matchesQuery: Bool
            if clean.isEmpty {
                matchesQuery = true
            } else {
                matchesQuery =
                    group.name
                        .lowercased()
                        .contains(clean) ||
                    group.locationName
                        .lowercased()
                        .contains(clean) ||
                    group.summary
                        .lowercased()
                        .contains(clean)
            }

            return matchesQuery &&
                discoverFilter.matches(
                    group
                )
        }
    }

    private var discoveryColumns:
        [GridItem] {
        [
            GridItem(
                .flexible(),
                spacing: 10
            ),
            GridItem(
                .flexible(),
                spacing: 10
            )
        ]
    }

    var body: some View {
        ZStack {
            ATHLTHPremiumCanvas(
                accent:
                    clubEmerald
                        .opacity(0.16)
            )

            ScrollView {
                LazyVStack(
                    alignment: .leading,
                    spacing: 18
                ) {
                    publicGroupSearchBar
                    introCard

                    if !groups.ownInvites
                        .isEmpty {
                        sectionHeader(
                            ATHLTHLocalization.choose(
                                english:
                                    "Invitations",
                                norwegian:
                                    "Invitasjoner"
                            )
                        )

                        ForEach(
                            groups.ownInvites,
                            id: \.groupID
                        ) {
                            invite in

                            if let group =
                                groups.group(
                                    for:
                                        invite
                                            .groupID
                                ) {
                                invitationCard(
                                    invite,
                                    group:
                                        group
                                )
                            }
                        }
                    }

                    if !groups.joinedGroups
                        .isEmpty {
                        sectionHeader(
                            ATHLTHLocalization.choose(
                                english:
                                    "My Clubs",
                                norwegian:
                                    "Mine Clubs"
                            )
                        )

                        ForEach(
                            groups.joinedGroups
                        ) {
                            group in

                            joinedGroupCard(
                                group
                            )
                        }
                    }

                    discoverySection
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 30)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(
            ATHLTHLocalization.choose(
                english: "Clubs",
                norwegian: "Klubber"
            )
        )
        .navigationBarTitleDisplayMode(
            .inline
        )
        .toolbar {
            ToolbarItem(
                placement:
                    .topBarTrailing
            ) {
                Button {
                    showingCreate = true
                } label: {
                    Image(
                        systemName: "plus"
                    )
                    .font(
                        .system(
                            size: 17,
                            weight:
                                .semibold
                        )
                    )
                    .foregroundStyle(
                        .white
                    )
                    .frame(
                        width: 38,
                        height: 38
                    )
                    .background(
                        LinearGradient(
                            colors: [
                                clubForest,
                                clubEmerald
                            ],
                            startPoint:
                                .topLeading,
                            endPoint:
                                .bottomTrailing
                        ),
                        in: Circle()
                    )
                    .shadow(
                        color:
                            clubForest
                                .opacity(
                                    0.16
                                ),
                        radius: 8,
                        y: 4
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    ATHLTHLocalization.choose(
                        english:
                            "Create Club",
                        norwegian:
                            "Opprett Club"
                    )
                )
            }
        }
        .sheet(
            isPresented:
                $showingCreate
        ) {
            CommunityGroupCreateView()
        }
        .task {
            await groups.refresh()
        }
        .refreshable {
            await groups.refresh()
        }
    }

    private var publicGroupSearchBar:
        some View {
        HStack(spacing: 10) {
            Image(
                systemName:
                    "magnifyingglass"
            )
            .font(
                .system(
                    size: 15,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                clubForest
            )

            TextField(
                ATHLTHLocalization.choose(
                    english:
                        "Search Clubs, places or activities",
                    norwegian:
                        "Søk Clubs, steder eller aktiviteter"
                ),
                text: $query
            )
            .textInputAutocapitalization(
                .never
            )
            .autocorrectionDisabled()

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(
                        systemName:
                            "xmark.circle.fill"
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                            .opacity(0.68)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    ATHLTHLocalization.choose(
                        english:
                            "Clear Club search",
                        norwegian:
                            "Tøm Club-søk"
                    )
                )
            }
        }
        .padding(.horizontal, 15)
        .frame(height: 50)
        .background(
            LinearGradient(
                colors: [
                    Color.white
                        .opacity(0.96),
                    clubMint
                        .opacity(0.62)
                ],
                startPoint:
                    .leading,
                endPoint:
                    .trailing
            ),
            in:
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(
                clubSage.opacity(
                    0.48
                ),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                clubForest.opacity(
                    0.04
                ),
            radius: 10,
            y: 4
        )
    }

    private var introCard:
        some View {
        ZStack(
            alignment: .leading
        ) {
            Image("CommunityHero")
                .resizable()
                .scaledToFill()
                .frame(
                    maxWidth:
                        .infinity
                )
                .frame(height: 112)
                .clipped()
                .opacity(0.78)

            LinearGradient(
                colors: [
                    clubMint
                        .opacity(0.98),
                    clubMint
                        .opacity(0.90),
                    Color.white
                        .opacity(0.28),
                    Color.clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            HStack(spacing: 13) {
                Image(
                    systemName:
                        "person.3.fill"
                )
                .font(
                    .system(
                        size: 20,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    .white
                )
                .frame(
                    width: 48,
                    height: 48
                )
                .background(
                    LinearGradient(
                        colors: [
                            clubForest,
                            clubEmerald
                        ],
                        startPoint:
                            .topLeading,
                        endPoint:
                            .bottomTrailing
                    ),
                    in:
                        RoundedRectangle(
                            cornerRadius: 15,
                            style:
                                .continuous
                        )
                )

                VStack(
                    alignment: .leading,
                    spacing: 4
                ) {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Train with your community",
                            norwegian:
                                "Tren med fellesskapet ditt"
                        )
                    )
                    .font(
                        .headline
                            .weight(.bold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Find public Clubs, train together and take on shared challenges.",
                            norwegian:
                                "Finn offentlige Clubs, tren sammen og delta i felles utfordringer."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                    .lineLimit(2)
                }

                Spacer(
                    minLength: 8
                )

                Image(
                    systemName:
                        "chevron.right"
                )
                .font(
                    .caption.bold()
                )
                .foregroundStyle(
                    .white
                        .opacity(0.92)
                )
                .frame(
                    width: 32,
                    height: 32
                )
                .background(
                    Color.black
                        .opacity(0.16),
                    in: Circle()
                )
            }
            .padding(14)
        }
        .frame(height: 112)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(
                    0.62
                ),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                clubForest.opacity(
                    0.07
                ),
            radius: 14,
            y: 6
        )
    }

    private var discoverySection:
        some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            sectionHeader(
                ATHLTHLocalization.choose(
                    english:
                        "Discover Clubs",
                    norwegian:
                        "Oppdag Clubs"
                ),
                actionTitle:
                    query.isEmpty &&
                    discoverFilter ==
                        .all
                        ? nil
                        : ATHLTHLocalization
                            .choose(
                                english:
                                    "Reset",
                                norwegian:
                                    "Nullstill"
                            ),
                action: {
                    withAnimation(
                        .easeInOut(
                            duration: 0.18
                        )
                    ) {
                        query = ""
                        discoverFilter =
                            .all
                    }
                }
            )

            discoveryFilters

            if matchingGroups
                .isEmpty {
                discoveryEmptyState
            } else {
                LazyVGrid(
                    columns:
                        discoveryColumns,
                    alignment:
                        .leading,
                    spacing: 10
                ) {
                    ForEach(
                        matchingGroups
                    ) {
                        group in

                        discoverGroupCard(
                            group
                        )
                    }
                }

                if groups
                    .canLoadMoreGroups {
                    Button {
                        Task {
                            await groups
                                .loadMoreGroups()
                        }
                    } label: {
                        HStack(
                            spacing: 8
                        ) {
                            if groups
                                .isLoadingMoreGroups {
                                ProgressView()
                                    .controlSize(
                                        .small
                                    )
                            }

                            Text(
                                groups
                                    .isLoadingMoreGroups
                                    ? ATHLTHLocalization
                                        .choose(
                                            english:
                                                "Loading more Clubs…",
                                            norwegian:
                                                "Laster flere Clubs…"
                                        )
                                    : ATHLTHLocalization
                                        .choose(
                                            english:
                                                "Load more Clubs",
                                            norwegian:
                                                "Last inn flere Clubs"
                                        )
                            )
                            .font(
                                .subheadline
                                    .weight(
                                        .semibold
                                    )
                            )
                        }
                        .foregroundStyle(
                            clubForest
                        )
                        .frame(
                            maxWidth:
                                .infinity
                        )
                        .frame(height: 42)
                        .background(
                            clubMint,
                            in:
                                RoundedRectangle(
                                    cornerRadius:
                                        15,
                                    style:
                                        .continuous
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(
                        groups
                            .isLoadingMoreGroups
                    )
                }
            }
        }
    }

    private var discoveryFilters:
        some View {
        ScrollView(
            .horizontal,
            showsIndicators: false
        ) {
            HStack(spacing: 8) {
                ForEach(
                    ClubDiscoveryFilter
                        .allCases
                ) {
                    filter in

                    Button {
                        withAnimation(
                            .easeInOut(
                                duration:
                                    0.16
                            )
                        ) {
                            discoverFilter =
                                filter
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(
                                systemName:
                                    filter.icon
                            )
                            .font(
                                .system(
                                    size: 11,
                                    weight:
                                        .semibold
                                )
                            )

                            Text(
                                filter.title
                            )
                        }
                        .font(
                            .caption
                                .weight(
                                    .semibold
                                )
                        )
                        .foregroundStyle(
                            discoverFilter ==
                                filter
                                ? Color.white
                                : ATHLTHTheme
                                    .primaryText
                        )
                        .padding(
                            .horizontal,
                            12
                        )
                        .frame(height: 34)
                        .background {
                            if discoverFilter ==
                                filter {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                clubForest,
                                                clubEmerald
                                            ],
                                            startPoint:
                                                .leading,
                                            endPoint:
                                                .trailing
                                        )
                                    )
                            } else {
                                Capsule()
                                    .fill(
                                        Color.white
                                            .opacity(
                                                0.90
                                            )
                                    )
                                    .overlay {
                                        Capsule()
                                            .stroke(
                                                clubSage
                                                    .opacity(
                                                        0.54
                                                    ),
                                                lineWidth:
                                                    0.7
                                            )
                                    }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private var discoveryEmptyState:
        some View {
        HStack(spacing: 13) {
            Image(
                systemName:
                    "person.3.sequence.fill"
            )
            .font(.title3)
            .foregroundStyle(
                clubForest
            )
            .frame(
                width: 46,
                height: 46
            )
            .background(
                clubMint,
                in:
                    RoundedRectangle(
                        cornerRadius: 14,
                        style:
                            .continuous
                    )
            )

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "No Clubs here yet",
                        norwegian:
                            "Ingen Clubs å vise ennå"
                    )
                )
                .font(
                    .subheadline
                        .weight(.bold)
                )

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Try another category or create a Club for your training community.",
                        norwegian:
                            "Prøv en annen kategori, eller opprett en Club for treningsmiljøet ditt."
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
            }

            Spacer()
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [
                    Color.white
                        .opacity(0.95),
                    clubMint
                        .opacity(0.66)
                ],
                startPoint:
                    .topLeading,
                endPoint:
                    .bottomTrailing
            ),
            in:
                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
            .stroke(
                clubSage.opacity(
                    0.48
                ),
                lineWidth: 0.8
            )
        }
    }

    private func invitationCard(
        _ invite:
            CommunityGroupInviteRecord,
        group:
            CommunityGroupRecord
    ) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                groupImage(
                    group,
                    size: 50,
                    cornerRadius: 15
                )

                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text(group.name)
                        .font(
                            .subheadline
                                .weight(
                                    .semibold
                                )
                        )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "You were invited to join",
                            norwegian:
                                "Du er invitert til å bli med"
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                }

                Spacer()
            }

            HStack(spacing: 10) {
                Button(
                    ATHLTHLocalization.choose(
                        english:
                            "Decline",
                        norwegian:
                            "Avslå"
                    )
                ) {
                    Task {
                        _ = await groups
                            .respondToInvite(
                                groupID:
                                    invite
                                        .groupID,
                                accept:
                                    false
                            )
                    }
                }
                .buttonStyle(
                    .bordered
                )
                .frame(
                    maxWidth: .infinity
                )

                Button(
                    ATHLTHLocalization.choose(
                        english:
                            "Join",
                        norwegian:
                            "Bli med"
                    )
                ) {
                    Task {
                        _ = await groups
                            .respondToInvite(
                                groupID:
                                    invite
                                        .groupID,
                                accept:
                                    true
                            )
                    }
                }
                .buttonStyle(
                    .borderedProminent
                )
                .tint(clubForest)
                .frame(
                    maxWidth: .infinity
                )
            }
        }
        .padding(14)
        .background(
            Color.white.opacity(
                0.94
            ),
            in:
                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
            .stroke(
                clubSage.opacity(
                    0.40
                ),
                lineWidth: 0.8
            )
        }
    }

    private func sectionHeader(
        _ title: String,
        actionTitle:
            String? = nil,
        action:
            @escaping () -> Void =
                {}
    ) -> some View {
        HStack(
            alignment: .center
        ) {
            Text(title)
                .font(
                    .title3
                        .weight(.bold)
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .primaryText
                )

            Spacer()

            if let actionTitle {
                Button(
                    action: action
                ) {
                    HStack(spacing: 4) {
                        Text(actionTitle)
                        Image(
                            systemName:
                                "chevron.right"
                        )
                    }
                    .font(
                        .caption
                            .weight(
                                .semibold
                            )
                    )
                    .foregroundStyle(
                        clubForest
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func joinedGroupCard(
        _ group:
            CommunityGroupRecord
    ) -> some View {
        NavigationLink {
            CommunityGroupDetailView(
                group: group
            )
        } label: {
            VStack(spacing: 0) {
                groupArtwork(group)
                    .frame(height: 66)
                    .frame(
                        maxWidth:
                            .infinity
                    )
                    .clipped()

                HStack(spacing: 11) {
                    groupImage(
                        group,
                        size: 54,
                        cornerRadius: 15
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: 15,
                            style:
                                .continuous
                        )
                        .stroke(
                            Color.white,
                            lineWidth: 2
                        )
                    }
                    .offset(y: -13)
                    .padding(
                        .bottom,
                        -13
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text(group.name)
                            .font(
                                .headline
                                    .weight(
                                        .bold
                                    )
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .primaryText
                            )
                            .lineLimit(1)

                        groupMetaLine(
                            group
                        )
                    }

                    Spacer(
                        minLength: 6
                    )

                    HStack(spacing: 5) {
                        Image(
                            systemName:
                                "checkmark"
                        )
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Member",
                                norwegian:
                                    "Medlem"
                            )
                        )
                    }
                    .font(
                        .caption2
                            .weight(
                                .semibold
                            )
                    )
                    .foregroundStyle(
                        clubForest
                    )
                    .padding(
                        .horizontal,
                        10
                    )
                    .frame(height: 30)
                    .background(
                        clubMint,
                        in: Capsule()
                    )

                    Image(
                        systemName:
                            "chevron.right"
                    )
                    .font(
                        .caption.bold()
                    )
                    .foregroundStyle(
                        clubForest
                            .opacity(0.52)
                    )
                }
                .padding(
                    .horizontal,
                    13
                )
                .padding(
                    .vertical,
                    11
                )
            }
            .background(
                Color.white.opacity(
                    0.96
                ),
                in:
                    RoundedRectangle(
                        cornerRadius: 22,
                        style:
                            .continuous
                    )
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
                .stroke(
                    clubSage.opacity(
                        0.44
                    ),
                    lineWidth: 0.8
                )
            }
            .shadow(
                color:
                    clubForest
                        .opacity(0.06),
                radius: 13,
                y: 6
            )
        }
        .buttonStyle(.plain)
    }

    private func discoverGroupCard(
        _ group:
            CommunityGroupRecord
    ) -> some View {
        let pending =
            groups.pendingJoinRequest(
                for: group.id
            ) != nil

        let inviteOnly =
            group.joinMode ==
                "invite_only"

        return VStack(
            alignment: .leading,
            spacing: 0
        ) {
            NavigationLink {
                CommunityGroupDetailView(
                    group: group
                )
            } label: {
                VStack(
                    alignment: .leading,
                    spacing: 0
                ) {
                    ZStack(
                        alignment:
                            .topLeading
                    ) {
                        groupArtwork(
                            group
                        )
                        .frame(height: 92)
                        .frame(
                            maxWidth:
                                .infinity
                        )
                        .clipped()

                        if !group
                            .locationName
                            .trimmingCharacters(
                                in:
                                    .whitespacesAndNewlines
                            )
                            .isEmpty {
                            Label(
                                group
                                    .locationName,
                                systemImage:
                                    "location.fill"
                            )
                            .font(
                                .system(
                                    size: 9.5,
                                    weight:
                                        .semibold
                                )
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .primaryText
                            )
                            .padding(
                                .horizontal,
                                8
                            )
                            .frame(
                                height: 25
                            )
                            .background(
                                Color.white
                                    .opacity(
                                        0.91
                                    ),
                                in: Capsule()
                            )
                            .padding(8)
                        }
                    }

                    VStack(
                        alignment: .leading,
                        spacing: 5
                    ) {
                        Text(group.name)
                            .font(
                                .subheadline
                                    .weight(
                                        .bold
                                    )
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .primaryText
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(
                                0.80
                            )

                        if !group.summary
                            .trimmingCharacters(
                                in:
                                    .whitespacesAndNewlines
                            )
                            .isEmpty {
                            Text(
                                group.summary
                            )
                            .font(
                                .system(
                                    size: 9.5
                                )
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .mutedText
                            )
                            .lineLimit(2)
                        } else {
                            groupMetaLine(
                                group
                            )
                        }
                    }
                    .padding(
                        .horizontal,
                        10
                    )
                    .padding(
                        .top,
                        9
                    )
                    .padding(
                        .bottom,
                        7
                    )
                }
            }
            .buttonStyle(.plain)

            Button {
                guard !pending,
                      !inviteOnly
                else {
                    return
                }

                Task {
                    _ = await groups
                        .requestJoin(
                            group
                        )
                }
            } label: {
                Text(
                    pending
                        ? ATHLTHLocalization
                            .choose(
                                english:
                                    "Requested",
                                norwegian:
                                    "Forespurt"
                            )
                        : inviteOnly
                            ? ATHLTHLocalization
                                .choose(
                                    english:
                                        "Invitation",
                                    norwegian:
                                        "Invitasjon"
                                )
                            : ATHLTHLocalization
                                .choose(
                                    english:
                                        "Join",
                                    norwegian:
                                        "Bli med"
                                )
                )
                .font(
                    .caption
                        .weight(
                            .semibold
                        )
                )
                .foregroundStyle(
                    clubForest
                )
                .frame(
                    maxWidth: .infinity
                )
                .frame(height: 34)
                .background(
                    clubMint,
                    in:
                        RoundedRectangle(
                            cornerRadius: 12,
                            style:
                                .continuous
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(
                pending ||
                inviteOnly
            )
            .padding(
                .horizontal,
                9
            )
            .padding(
                .bottom,
                9
            )
        }
        .background(
            Color.white.opacity(
                0.96
            ),
            in:
                RoundedRectangle(
                    cornerRadius: 18,
                    style:
                        .continuous
                )
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(
                clubSage.opacity(
                    0.42
                ),
                lineWidth: 0.7
            )
        }
        .shadow(
            color:
                clubForest.opacity(
                    0.045
                ),
            radius: 10,
            y: 4
        )
    }

    @ViewBuilder
    private func groupArtwork(
        _ group:
            CommunityGroupRecord
    ) -> some View {
        if let reference =
                group.headerImageURL ??
                group.imageURL,
           !reference
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
                .isEmpty {
            ATHLTHArtworkImage(
                reference: reference,
                fallbackAssetName:
                    "CommunityHero"
            )
            .athlthBoundedFill()
        } else {
            Image(
                "CommunityHero"
            )
            .resizable()
            .interpolation(.medium)
            .scaledToFill()
            .athlthBoundedFill()
        }
    }

    @ViewBuilder
    private func groupMetaLine(
        _ group:
            CommunityGroupRecord
    ) -> some View {
        let memberCount =
            groups.members(
                in: group.id
            ).count

        HStack(spacing: 5) {
            Image(
                systemName:
                    group.visibility ==
                        "private"
                        ? "lock.fill"
                        : "globe"
            )

            Text(
                group.visibility ==
                    "private"
                    ? ATHLTHLocalization
                        .choose(
                            english:
                                "Private",
                            norwegian:
                                "Privat"
                        )
                    : ATHLTHLocalization
                        .choose(
                            english:
                                "Public",
                            norwegian:
                                "Offentlig"
                        )
            )

            if memberCount > 0 {
                Text("·")
                Text(
                    ATHLTHLocalization.counted(
                        memberCount,
                        englishSingular:
                            "member",
                        englishPlural:
                            "members",
                        norwegianSingular:
                            "medlem",
                        norwegianPlural:
                            "medlemmer"
                    )
                )
            }
        }
        .font(
            .caption2
                .weight(.medium)
        )
        .foregroundStyle(
            ATHLTHTheme
                .mutedText
        )
        .lineLimit(1)
    }

    @ViewBuilder
    private func groupImage(
        _ group:
            CommunityGroupRecord,
        size: CGFloat,
        cornerRadius: CGFloat
    ) -> some View {
        if let value =
                group.imageURL,
           let url =
                URL(string: value) {
            ATHLTHStorageImage(url: url) {
                phase in

                switch phase {
                case .success(
                    let image
                ):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    groupImageFallback
                }
            }
            .frame(
                width: size,
                height: size
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius:
                        cornerRadius,
                    style:
                        .continuous
                )
            )
        } else {
            groupImageFallback
                .frame(
                    width: size,
                    height: size
                )
        }
    }

    private var groupImageFallback:
        some View {
        Image(
            systemName:
                "person.3.fill"
        )
        .font(
            .system(
                size: 18,
                weight: .semibold
            )
        )
        .foregroundStyle(
            clubForest
        )
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
        .background(
            clubMint,
            in:
                RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
        )
    }
}

struct CommunityGroupDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var groups: CommunityGroupStore
    @EnvironmentObject private var session: AppSessionStore

    let group: CommunityGroupRecord

    @State private var selectedTab: CommunityGroupsTab = .overview
    @State private var tabIndicator: CommunityGroupsTab = .overview
    @State private var messageDraft = ""
    @State private var showingCreateEvent = false
    @State private var showingCreateChallenge = false
    @State private var showingGroupSettings = false
    @State private var showingNotificationSettings = false
    @State private var updateDraft = ""
    @State private var postingUpdate = false
    @State private var showAllClubPosts = false
    @FocusState private var updateComposerFocused: Bool

    // Club-only premium green palette. Keeping this local prevents the
    // Community redesign from changing the visual language elsewhere.
    private var clubForest: Color {
        Color(red: 0.025, green: 0.30, blue: 0.21)
    }

    private var clubEmerald: Color {
        Color(red: 0.055, green: 0.49, blue: 0.32)
    }

    private var clubLeaf: Color {
        Color(red: 0.18, green: 0.62, blue: 0.35)
    }

    private var clubMint: Color {
        Color(red: 0.90, green: 0.96, blue: 0.92)
    }

    private var clubSage: Color {
        Color(red: 0.77, green: 0.88, blue: 0.81)
    }

    private var currentGroup: CommunityGroupRecord {
        groups.groups.first {
            $0.id == group.id
        } ??
        groups.searchResults.first {
            $0.id == group.id
        } ??
        group
    }

    private var isMember: Bool {
        groups.joinedGroupIDs.contains(group.id)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ATHLTHPremiumCanvas(
                    accent: clubEmerald.opacity(0.16)
                )

                if isMember && selectedTab == .chat {
                    VStack(spacing: 0) {
                        groupHeader(
                            topInset:
                                geometry.safeAreaInsets.top,
                            availableWidth:
                                geometry.size.width
                        )

                        groupAreaPicker
                            .frame(
                                width: max(
                                    0,
                                    min(
                                        geometry.size.width - 28,
                                        760
                                    )
                                )
                            )
                            .padding(.vertical, 11)
                            .frame(maxWidth: .infinity)
                            .background(
                                ATHLTHTheme.canvasTop
                                    .opacity(0.96)
                            )

                        Divider()
                            .opacity(0.55)

                        chat
                            .frame(maxHeight: .infinity)
                    }
                    .ignoresSafeArea(edges: .top)
                    .frame(
                        width: geometry.size.width
                    )
                    .frame(
                        maxHeight: .infinity
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            groupHeader(
                                topInset:
                                    geometry.safeAreaInsets.top,
                                availableWidth:
                                    geometry.size.width
                            )

                            VStack(spacing: 12) {
                                if isMember {
                                    groupAreaPicker

                                    switch selectedTab {
                                    case .overview:
                                        overview
                                    case .chat:
                                        EmptyView()
                                    case .events:
                                        events
                                    case .challenges:
                                        challenges
                                    }
                                } else {
                                    membershipAccessCard
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.top, 10)
                            .padding(.bottom, 30)
                            .frame(maxWidth: 760)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .ignoresSafeArea(edges: .top)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingCreateEvent) {
            CommunityGroupEventCreateView(
                group: currentGroup
            )
        }
        .sheet(isPresented: $showingCreateChallenge) {
            CommunityGroupChallengeCreateView(
                group: currentGroup
            )
        }
        .sheet(isPresented: $showingGroupSettings) {
            CommunityGroupSettingsView(
                group: currentGroup
            )
        }
        .sheet(isPresented: $showingNotificationSettings) {
            CommunityGroupNotificationSettingsView(
                group: currentGroup
            )
        }
        .task {
            if groups.groups.isEmpty {
                await groups.refresh()
            }

            if isMember ||
                currentGroup.creatorID ==
                    session.profile.userID {
                await groups.loadGroupContent(
                    group.id
                )
            }
        }
        .onChange(
            of: groups.groups.map(\.id)
        ) { _, groupIDs in
            let isSearchResult =
                groups.searchResults.contains {
                    $0.id == group.id
                }

            if !groupIDs.contains(group.id) &&
                !isSearchResult {
                dismiss()
            }
        }
    }

    private func selectTab(
        _ tab: CommunityGroupsTab
    ) {
        if selectedTab != tab {
            var transaction = Transaction()
            transaction.disablesAnimations = true

            withTransaction(transaction) {
                selectedTab = tab
            }
        }

        guard tabIndicator != tab else {
            return
        }

        withAnimation(
            .easeOut(
                duration: 0.14
            )
        ) {
            tabIndicator = tab
        }
    }

    private var groupAreaPicker: some View {
        HStack(spacing: 3) {
            ForEach(
                CommunityGroupsTab.allCases
            ) { tab in
                Button {
                    // Swap heavy tab content outside an animation transaction.
                    // Only the compact selection indicator animates.
                    selectTab(tab)
                } label: {
                    Text(tab.displayTitle)
                        .font(
                            .system(
                                size: 13,
                                weight:
                                    tabIndicator == tab
                                        ? .semibold
                                        : .medium
                            )
                        )
                        .foregroundStyle(
                            tabIndicator == tab
                                ? Color.white
                                : ATHLTHTheme
                                    .primaryText
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.66)
                        .frame(
                            maxWidth: .infinity
                        )
                        .frame(height: 42)
                        .background {
                            if tabIndicator == tab {
                                RoundedRectangle(
                                    cornerRadius: 15,
                                    style: .continuous
                                )
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            clubForest,
                                            clubEmerald
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .shadow(
                                    color:
                                        clubEmerald
                                            .opacity(0.12),
                                    radius: 7,
                                    y: 3
                                )
                            }
                        }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(4)
        .background(
            ATHLTHTheme.card.opacity(0.96),
            in:
                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
            .stroke(
                clubEmerald
                    .opacity(0.16),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                clubForest
                    .opacity(0.05),
            radius: 10,
            y: 4
        )
    }

    private var membershipAccessCard: some View {
        ATHLTHCard {
            if groups.pendingInvite(
                for: currentGroup.id
            ) != nil {
                Text("You have a group invitation")
                    .font(.headline)
                Text(
                    "Accept the invitation to unlock chat, events and challenges."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 3)

                HStack(spacing: 10) {
                    Button("Decline") {
                        Task {
                            _ = await groups.respondToInvite(
                                groupID: currentGroup.id,
                                accept: false
                            )
                        }
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)

                    Button("Join Group") {
                        Task {
                            _ = await groups.respondToInvite(
                                groupID: currentGroup.id,
                                accept: true
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(clubForest)
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, 12)
            } else if groups.pendingJoinRequest(
                for: currentGroup.id
            ) != nil {
                Label(
                    "Membership request pending",
                    systemImage: "clock.fill"
                )
                .font(.headline)

                Text(
                    "An Owner or Admin can approve your request."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            } else if currentGroup.joinMode == "invite_only" {
                Label(
                    "Invitation required",
                    systemImage: "envelope.badge"
                )
                .font(.headline)

                Text(
                    "This group only accepts members who have been invited by an Owner or Admin."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            } else {
                Text(
                    currentGroup.joinMode == "approval"
                        ? "Request membership to unlock group chat, events and challenges."
                        : "Join to unlock group chat, events and challenges."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Button {
                    Task {
                        _ = await groups.requestJoin(
                            currentGroup
                        )
                    }
                } label: {
                    Label(
                        currentGroup.joinMode == "approval"
                            ? "Request to Join"
                            : "Join Group",
                        systemImage:
                            currentGroup.joinMode == "approval"
                                ? "person.badge.clock"
                                : "person.badge.plus"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(clubForest)
                .padding(.top, 8)
            }
        }
    }

    private func groupHeader(
        topInset: CGFloat,
        availableWidth: CGFloat
    ) -> some View {
        ZStack(alignment: .bottomLeading) {
            groupHeroBackground

            LinearGradient(
                colors: [
                    Color.black.opacity(0.05),
                    Color.black.opacity(0.20),
                    Color.black.opacity(0.72)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            LinearGradient(
                colors: [
                    Color.black.opacity(0.42),
                    Color.clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            VStack {
                HStack(spacing: 10) {
                    Button {
                        dismiss()
                    } label: {
                        headerCircleButton(
                            icon: "chevron.left"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        ATHLTHLocalization.choose(
                            english: "Back",
                            norwegian: "Tilbake"
                        )
                    )

                    Spacer()

                    if groups.canManage(
                        currentGroup
                    ) {
                        Button {
                            showingGroupSettings = true
                        } label: {
                            headerCircleButton(
                                icon:
                                    "photo.on.rectangle.angled"
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            ATHLTHLocalization.choose(
                                english:
                                    "Change Club header image",
                                norwegian:
                                    "Endre headerbilde"
                            )
                        )
                    }

                    if isMember ||
                        currentGroup.creatorID ==
                            session.profile.userID {
                        NavigationLink {
                            CommunityGroupMembersView(
                                group: currentGroup
                            )
                        } label: {
                            headerCircleButton(
                                icon: "person.2.fill"
                            )
                        }
                        .buttonStyle(.plain)

                        Menu {
                            if groups.canManage(
                                currentGroup
                            ) {
                                Button {
                                    showingGroupSettings =
                                        true
                                } label: {
                                    Label(
                                        ATHLTHLocalization
                                            .choose(
                                                english:
                                                    "Club Settings",
                                                norwegian:
                                                    "Club-innstillinger"
                                            ),
                                        systemImage:
                                            "gearshape"
                                    )
                                }
                            }

                            Button {
                                showingNotificationSettings =
                                    true
                            } label: {
                                Label(
                                    ATHLTHLocalization
                                        .choose(
                                            english:
                                                "Notifications",
                                            norwegian:
                                                "Varsler"
                                        ),
                                    systemImage: "bell"
                                )
                            }

                            if !groups.isOwner(
                                of: currentGroup
                            ) {
                                Button(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Leave Club",
                                        norwegian:
                                            "Forlat Club"
                                    ),
                                    role: .destructive
                                ) {
                                    Task {
                                        await groups.leave(
                                            currentGroup
                                        )
                                    }
                                }
                            }
                        } label: {
                            headerCircleButton(
                                icon: "ellipsis"
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(
                    .top,
                    max(topInset + 8, 18)
                )

                Spacer()
            }

            HStack(
                alignment: .bottom,
                spacing: 14
            ) {
                if groups.canManage(
                    currentGroup
                ) {
                    Button {
                        showingGroupSettings = true
                    } label: {
                        detailGroupImage
                    }
                    .buttonStyle(.plain)
                    .layoutPriority(1)
                } else {
                    detailGroupImage
                        .layoutPriority(1)
                }

                VStack(
                    alignment: .leading,
                    spacing: 5
                ) {
                    Text(currentGroup.name)
                        .font(
                            .system(
                                size: 31,
                                weight: .bold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                        .shadow(
                            color:
                                .black.opacity(
                                    0.20
                                ),
                            radius: 4,
                            y: 1
                        )

                    if !currentGroup.summary
                        .trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        )
                        .isEmpty {
                        Text(
                            currentGroup.summary
                        )
                        .font(.subheadline)
                        .foregroundStyle(
                            .white.opacity(0.92)
                        )
                        .lineLimit(2)
                    }

                    HStack(spacing: 7) {
                        clubHeaderChip(
                            currentGroup.visibility ==
                                "private"
                                ? ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Private",
                                        norwegian:
                                            "Privat"
                                    )
                                : ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Public",
                                        norwegian:
                                            "Offentlig"
                                    ),
                            icon:
                                currentGroup.visibility ==
                                    "private"
                                    ? "lock.fill"
                                    : "globe"
                        )

                        clubHeaderChip(
                            memberCountText,
                            icon:
                                "person.2.fill"
                        )

                        if !currentGroup.locationName
                            .trimmingCharacters(
                                in:
                                    .whitespacesAndNewlines
                            )
                            .isEmpty {
                            clubHeaderChip(
                                currentGroup
                                    .locationName,
                                icon:
                                    "location.fill"
                            )
                        }
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
                .clipped()

                Spacer(minLength: 0)
            }
            // Constrain the identity row to the physical viewport. Without an
            // explicit width, long Club copy/chips can give the HStack a wider
            // ideal size inside ScrollView, which centers the row and pushes
            // the Club profile image partly off the left edge.
            .frame(
                width: max(
                    availableWidth - 36,
                    0
                ),
                alignment: .leading
            )
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        // A ScrollView proposes an unbounded horizontal ideal size to some
        // descendants. Pin the hero to the physical viewport so the identity
        // row (including the Club profile image) cannot be centered in an
        // oversized header and disappear beyond the left/right edge.
        .frame(
            width: max(availableWidth, 0),
            height: 238 + max(topInset, 0)
        )
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 28,
                bottomTrailingRadius: 28,
                topTrailingRadius: 0,
                style: .continuous
            )
        )
        .shadow(
            color:
                clubForest
                    .opacity(0.10),
            radius: 18,
            y: 7
        )
    }

    private func headerCircleButton(
        icon: String
    ) -> some View {
        Image(systemName: icon)
            .font(
                .system(
                    size: 15,
                    weight: .semibold
                )
            )
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(
                Color.black.opacity(0.28),
                in: Circle()
            )
            .overlay {
                Circle()
                    .stroke(
                        Color.white.opacity(0.28),
                        lineWidth: 0.8
                    )
            }
    }

    private func clubHeaderChip(
        _ title: String,
        icon: String
    ) -> some View {
        Label(title, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white.opacity(0.92))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                Color.black.opacity(0.24),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(
                        Color.white.opacity(0.18),
                        lineWidth: 0.7
                    )
            }
    }

    @ViewBuilder
    private var groupHeroBackground: some View {
        if let value =
                currentGroup.headerImageURL {
            ATHLTHArtworkImage(
                reference: value,
                fallbackAssetName:
                    "CommunityHero"
            )
            .athlthBoundedFill()
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
            .clipped()
        } else {
            groupHeroFallback
        }
    }

    private var groupHeroFallback: some View {
        ZStack {
            Image("CommunityHero")
                .resizable()
                .interpolation(.medium)
                .scaledToFill()

            LinearGradient(
                colors: [
                    clubForest.opacity(0.10),
                    clubLeaf.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .clipped()
    }

    @ViewBuilder
    private var detailGroupImage: some View {
        Group {
            if let value = currentGroup.imageURL,
               let url = URL(string: value) {
                ATHLTHStorageImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        detailGroupImageFallback
                    }
                }
            } else {
                detailGroupImageFallback
            }
        }
        .frame(width: 76, height: 76)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.90),
                lineWidth: 2
            )
        }
        .shadow(
            color: Color.black.opacity(0.20),
            radius: 12,
            y: 5
        )
    }

    private var detailGroupImageFallback: some View {
        Image(systemName: "person.3.fill")
            .font(.system(size: 31, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(
                    colors: [
                        clubForest,
                        clubEmerald
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private var memberCountText: String {
        let count = groups.members(in: group.id).count

        return ATHLTHLocalization.format(
            english:
                count == 1
                    ? "%d member"
                    : "%d members",
            norwegian:
                count == 1
                    ? "%d medlem"
                    : "%d medlemmer",
            count
        )
    }

    private var overview: some View {
        VStack(spacing: 12) {
            if groups.canPublishUpdates(
                currentGroup
            ) {
                referenceClubComposer
            }

            referenceClubPostsSection

            if let challenge =
                featuredClubChallenge ??
                nextGroupChallenge {
                referenceClubChallengeCard(
                    challenge
                )
            }

            referenceComingUpSection

            if featuredClubChallenge == nil,
               nextGroupChallenge == nil,
               nextGroupEvent == nil,
               referenceSecondaryChallenge == nil {
                referenceEmptyChallengeCard
            }

            clubLeaderboardCard
        }
    }

    private var referenceClubComposer: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                if let profile =
                    groups.profileCard(
                        for:
                            session.profile.userID
                    ) {
                    CommunityGroupProfileAvatar(
                        profile: profile,
                        size: 42
                    )
                } else {
                    Circle()
                        .fill(
                            clubMint
                        )
                        .frame(
                            width: 42,
                            height: 42
                        )
                        .overlay {
                            Image(
                                systemName:
                                    "person.fill"
                            )
                            .foregroundStyle(
                                clubForest
                            )
                        }
                }

                TextField(
                    ATHLTHLocalization.choose(
                        english:
                            "Write a post in \(currentGroup.name)…",
                        norwegian:
                            "Skriv et innlegg i \(currentGroup.name)…"
                    ),
                    text: $updateDraft,
                    axis: .vertical
                )
                .focused(
                    $updateComposerFocused
                )
                .lineLimit(1...4)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    Color.white.opacity(0.94),
                    in:
                        RoundedRectangle(
                            cornerRadius: 17,
                            style: .continuous
                        )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 17,
                        style: .continuous
                    )
                    .stroke(
                        Color.black.opacity(0.04),
                        lineWidth: 0.7
                    )
                }

                Button {
                    postReferenceClubUpdate()
                } label: {
                    Group {
                        if postingUpdate {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(
                                systemName:
                                    "arrow.up"
                            )
                            .font(
                                .system(
                                    size: 17,
                                    weight: .bold
                                )
                            )
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(
                        width: 46,
                        height: 46
                    )
                    .background(
                        LinearGradient(
                            colors: [
                                clubForest,
                                clubEmerald
                            ],
                            startPoint:
                                .topLeading,
                            endPoint:
                                .bottomTrailing
                        ),
                        in: Circle()
                    )
                    .shadow(
                        color:
                            clubForest
                                .opacity(0.18),
                        radius: 8,
                        y: 4
                    )
                }
                .buttonStyle(.plain)
                .disabled(
                    updateDraft
                        .trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        )
                        .isEmpty ||
                    updateDraft.count > 1200 ||
                    postingUpdate
                )
            }

            HStack(spacing: 8) {
                if groups.canManage(
                    currentGroup
                ) {
                    Button {
                        showingGroupSettings = true
                    } label: {
                        referenceActionTile(
                            title:
                                ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Manage",
                                        norwegian:
                                            "Administrer"
                                    ),
                            detail:
                                ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Club settings",
                                        norwegian:
                                            "Club-innstillinger"
                                    ),
                            icon:
                                "slider.horizontal.3",
                            tint:
                                clubEmerald
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        selectTab(.chat)
                    } label: {
                        referenceActionTile(
                            title: "Chat",
                            detail:
                                ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Talk together",
                                        norwegian:
                                            "Snakk sammen"
                                    ),
                            icon:
                                "bubble.left.and.bubble.right.fill",
                            tint:
                                clubForest
                        )
                    }
                    .buttonStyle(.plain)
                }

                NavigationLink {
                    CommunityGroupMembersView(
                        group: currentGroup
                    )
                } label: {
                    referenceActionTile(
                        title:
                            groups.canManage(
                                currentGroup
                            )
                                ? ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Invite",
                                        norwegian:
                                            "Inviter"
                                    )
                                : ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Members",
                                        norwegian:
                                            "Medlemmer"
                                    ),
                        detail:
                            groups.canManage(
                                currentGroup
                            )
                                ? ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Add people",
                                        norwegian:
                                            "Få med flere"
                                    )
                                : memberCountText,
                        icon:
                            groups.canManage(
                                currentGroup
                            )
                                ? "person.badge.plus"
                                : "person.2.fill",
                        tint:
                            clubForest
                    )
                }
                .buttonStyle(.plain)

                referenceChallengeAction

                Button {
                    if groups
                        .canCreateGroupContent(
                            currentGroup
                        ) {
                        showingCreateEvent = true
                    } else {
                        selectTab(.events)
                    }
                } label: {
                    referenceActionTile(
                        title:
                            ATHLTHLocalization
                                .choose(
                                    english:
                                        "New event",
                                    norwegian:
                                        "Nytt event"
                                ),
                        detail:
                            groups
                                .canCreateGroupContent(
                                    currentGroup
                                )
                                ? ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Create",
                                        norwegian:
                                            "Opprett"
                                    )
                                : ATHLTHLocalization
                                    .choose(
                                        english:
                                            "View",
                                        norwegian:
                                            "Se events"
                                    ),
                        icon: "calendar",
                        tint:
                            clubEmerald
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(13)
        .background(
            Color.white.opacity(0.94),
            in:
                RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
            .stroke(
                Color.black.opacity(0.04),
                lineWidth: 0.7
            )
        }
        .shadow(
            color:
                clubForest
                    .opacity(0.05),
            radius: 12,
            y: 5
        )
    }

    @ViewBuilder
    private var referenceChallengeAction:
        some View {
        if let challenge =
            featuredClubChallenge ??
            nextGroupChallenge {
            NavigationLink {
                CommunityGroupChallengeDetailView(
                    group: currentGroup,
                    challenge: challenge
                )
            } label: {
                referenceActionTile(
                    title:
                        ATHLTHLocalization
                            .choose(
                                english:
                                    "Club challenge",
                                norwegian:
                                    "Ukens challenge"
                            ),
                    detail:
                        ATHLTHLocalization
                            .choose(
                                english:
                                    "Join in",
                                norwegian:
                                    "Bli med"
                            ),
                    icon: "trophy.fill",
                    tint:
                        clubEmerald
                )
            }
            .buttonStyle(.plain)
        } else {
            Button {
                if groups
                    .canCreateGroupContent(
                        currentGroup
                    ) {
                    showingCreateChallenge =
                        true
                } else {
                    selectTab(.challenges)
                }
            } label: {
                referenceActionTile(
                    title:
                        ATHLTHLocalization
                            .choose(
                                english:
                                    "Club challenge",
                                norwegian:
                                    "Ukens challenge"
                            ),
                    detail:
                        groups
                            .canCreateGroupContent(
                                currentGroup
                            )
                            ? ATHLTHLocalization
                                .choose(
                                    english:
                                        "Create",
                                    norwegian:
                                        "Opprett"
                                )
                            : ATHLTHLocalization
                                .choose(
                                    english:
                                        "View",
                                    norwegian:
                                        "Se challenges"
                                ),
                    icon: "trophy.fill",
                    tint:
                        clubEmerald
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func referenceActionTile(
        title: String,
        detail: String,
        icon: String,
        tint: Color
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 5
        ) {
            HStack {
                Image(systemName: icon)
                    .font(
                        .system(
                            size: 16,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(.white)
                    .frame(
                        width: 34,
                        height: 34
                    )
                    .background(
                        tint,
                        in: Circle()
                    )

                Spacer(minLength: 2)

                Image(
                    systemName:
                        "chevron.right"
                )
                .font(.caption2.bold())
                .foregroundStyle(
                    tint.opacity(0.82)
                )
            }

            Text(title)
                .font(
                    .caption.weight(
                        .bold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .primaryText
                )
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .frame(
                    height: 30,
                    alignment: .topLeading
                )

            Text(detail)
                .font(
                    .system(
                        size: 9,
                        weight: .medium
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
                .lineLimit(2)
                .minimumScaleFactor(0.70)
                .frame(
                    height: 24,
                    alignment: .topLeading
                )
        }
        .padding(10)
        .frame(
            maxWidth: .infinity,
            alignment: .topLeading
        )
        .frame(
            height: 108,
            alignment: .topLeading
        )
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.98),
                    clubMint.opacity(0.78),
                    tint.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in:
                RoundedRectangle(
                    cornerRadius: 17,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 17,
                style: .continuous
            )
            .stroke(
                clubSage.opacity(0.62),
                lineWidth: 0.8
            )
        }
    }

    private func postReferenceClubUpdate() {
        let body =
            updateDraft
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

        guard !body.isEmpty,
              body.count <= 1200,
              !postingUpdate
        else {
            return
        }

        updateDraft = ""
        updateComposerFocused = false

        Task {
            postingUpdate = true

            let posted =
                await groups
                    .postAnnouncement(
                        groupID: group.id,
                        body: body
                    )

            postingUpdate = false

            if !posted {
                updateDraft = body
            }
        }
    }

    private var referenceEmptyChallengeCard:
        some View {
        let canCreate =
            groups.canCreateGroupContent(
                currentGroup
            )

        return Button {
            if canCreate {
                showingCreateChallenge = true
            } else {
                selectTab(.challenges)
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    clubEmerald
                                        .opacity(0.92),
                                    clubLeaf.opacity(0.88)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Image(
                        systemName:
                            "trophy.fill"
                    )
                    .font(
                        .system(
                            size: 25,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(.white)
                }
                .frame(width: 58, height: 58)
                .shadow(
                    color:
                        clubEmerald
                            .opacity(0.20),
                    radius: 10,
                    y: 4
                )

                VStack(
                    alignment: .leading,
                    spacing: 5
                ) {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "CLUB CHALLENGE",
                            norwegian:
                                "CLUB CHALLENGE"
                        )
                    )
                    .font(
                        .system(
                            size: 9,
                            weight: .bold
                        )
                    )
                    .tracking(0.8)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )

                    Text(
                        canCreate
                            ? ATHLTHLocalization
                                .choose(
                                    english:
                                        "No challenge selected yet",
                                    norwegian:
                                        "Ingen challenge valgt ennå"
                                )
                            : ATHLTHLocalization
                                .choose(
                                    english:
                                        "No active Club challenge",
                                    norwegian:
                                        "Ingen aktiv Club challenge"
                                )
                    )
                    .font(
                        .headline.weight(
                            .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                    .lineLimit(2)

                    Text(
                        canCreate
                            ? ATHLTHLocalization
                                .choose(
                                    english:
                                        "Create the Club's next challenge. Owner and Admin can feature it when it is ready.",
                                    norwegian:
                                        "Opprett klubbens neste challenge. Owner og Admin kan fremheve den når den er klar."
                                )
                            : ATHLTHLocalization
                                .choose(
                                    english:
                                        "When an Admin chooses the next challenge, it will appear here.",
                                    norwegian:
                                        "Når en Admin velger neste challenge, vises den her."
                                )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                    .lineLimit(3)

                    HStack(spacing: 5) {
                        Text(
                            canCreate
                                ? ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Create challenge",
                                        norwegian:
                                            "Opprett challenge"
                                    )
                                : ATHLTHLocalization
                                    .choose(
                                        english:
                                            "See challenges",
                                        norwegian:
                                            "Se challenges"
                                    )
                        )

                        Image(
                            systemName:
                                "arrow.right"
                        )
                    }
                    .font(
                        .caption.weight(
                            .semibold
                        )
                    )
                    .foregroundStyle(
                        clubForest
                    )
                }

                Spacer(minLength: 4)

                Image(
                    systemName:
                        "chevron.right"
                )
                .font(.caption.bold())
                .foregroundStyle(
                    clubForest
                        .opacity(0.65)
                )
            }
            .padding(16)
            .frame(
                maxWidth: .infinity,
                minHeight: 138,
                alignment: .leading
            )
            .background(
                LinearGradient(
                    colors: [
                        Color.white
                            .opacity(0.96),
                        clubMint
                            .opacity(0.72),
                        ATHLTHTheme
                            .card
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in:
                    RoundedRectangle(
                        cornerRadius: 21,
                        style: .continuous
                    )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 21,
                    style: .continuous
                )
                .stroke(
                    clubEmerald
                        .opacity(0.18),
                    lineWidth: 0.8
                )
            }
            .shadow(
                color:
                    clubForest
                        .opacity(0.06),
                radius: 12,
                y: 5
            )
        }
        .buttonStyle(.plain)
    }

    private func referenceClubChallengeCard(
        _ challenge:
            CommunityGroupChallengeRecord
    ) -> some View {
        NavigationLink {
            CommunityGroupChallengeDetailView(
                group: currentGroup,
                challenge: challenge
            )
        } label: {
            ZStack(alignment: .bottomLeading) {
                referenceChallengeArtwork(
                    challenge
                )

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.04),
                        Color.black.opacity(0.20),
                        Color.black.opacity(0.72)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                LinearGradient(
                    colors: [
                        clubForest
                            .opacity(0.58),
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                VStack(
                    alignment: .leading,
                    spacing: 6
                ) {
                    HStack {
                        Label(
                            ATHLTHLocalization.choose(
                                english:
                                    "CLUB CHALLENGE",
                                norwegian:
                                    "UKENS CHALLENGE"
                            ),
                            systemImage:
                                "trophy.fill"
                        )
                        .font(
                            .system(
                                size: 9,
                                weight: .bold
                            )
                        )
                        .tracking(0.7)
                        .foregroundStyle(
                            .white.opacity(0.94)
                        )
                        .padding(
                            .horizontal,
                            10
                        )
                        .frame(height: 26)
                        .background(
                            Color.black
                                .opacity(0.22),
                            in: Capsule()
                        )
                        .overlay {
                            Capsule()
                                .stroke(
                                    Color.white
                                        .opacity(
                                            0.22
                                        ),
                                    lineWidth:
                                        0.7
                                )
                        }

                        Spacer()

                        Text(
                            ATHLTHLocalization.choose(
                                english: "Join",
                                norwegian: "Bli med"
                            )
                        )
                        .font(
                            .caption.weight(
                                .bold
                            )
                        )
                        .foregroundStyle(
                            clubForest
                        )
                        .padding(
                            .horizontal,
                            13
                        )
                        .frame(height: 34)
                        .background(
                            .white,
                            in: Capsule()
                        )
                    }

                    Spacer(minLength: 0)

                    Text(challenge.title)
                        .font(
                            .system(
                                size: 21,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    if !challenge.summary
                        .isEmpty {
                        Text(
                            challenge.summary
                        )
                        .font(.caption)
                        .foregroundStyle(
                            .white.opacity(0.88)
                        )
                        .lineLimit(2)
                    }

                    HStack(spacing: 7) {
                        Label(
                            comingUpChallengeDetail(
                                challenge
                            ),
                            systemImage:
                                "clock"
                        )
                        .font(.caption2)
                        .foregroundStyle(
                            .white.opacity(0.86)
                        )
                        .lineLimit(1)

                        Spacer()

                        let contributors =
                            Set(
                                groups
                                    .challengeWorkouts
                                    .filter {
                                        $0.challengeID ==
                                            challenge.id
                                    }
                                    .map(\.userID)
                            )
                            .count

                        if contributors > 0 {
                            Label(
                                "\(contributors)",
                                systemImage:
                                    "person.2.fill"
                            )
                            .font(
                                .caption2
                                    .weight(
                                        .semibold
                                    )
                            )
                            .foregroundStyle(
                                .white
                            )
                        }
                    }
                }
                .padding(14)
            }
            .frame(height: 156)
            .frame(maxWidth: .infinity)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 21,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 21,
                    style: .continuous
                )
                .stroke(
                    Color.white
                        .opacity(0.16),
                    lineWidth: 0.8
                )
            }
            .shadow(
                color:
                    clubForest
                        .opacity(0.12),
                radius: 13,
                y: 6
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func referenceChallengeArtwork(
        _ challenge:
            CommunityGroupChallengeRecord
    ) -> some View {
        if let reference =
                challenge.imageURL,
           !reference
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
                .isEmpty {
            ATHLTHArtworkImage(
                reference: reference,
                fallbackAssetName:
                    "CommunityHero"
            )
            .athlthBoundedFill()
        } else {
            ZStack {
                LinearGradient(
                    colors: [
                        clubForest,
                        clubLeaf
                            .opacity(0.82),
                        clubEmerald
                            .opacity(0.72)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Image(
                    systemName:
                        "trophy.fill"
                )
                .font(
                    .system(
                        size: 66,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    .white.opacity(0.16)
                )
                .offset(
                    x: 104,
                    y: -18
                )
            }
        }
    }

    private var referenceComingUpSection:
        some View {
        VStack(spacing: 10) {
            referenceClubSectionHeader(
                icon: "calendar",
                title:
                    ATHLTHLocalization
                        .choose(
                            english:
                                "Coming up",
                            norwegian:
                                "Kommende"
                        ),
                subtitle:
                    ATHLTHLocalization
                        .choose(
                            english:
                                "The next event or challenge in the Club",
                            norwegian:
                                "Neste event eller challenge i gruppen"
                        ),
                actionTitle:
                    ATHLTHLocalization
                        .choose(
                            english: "See all",
                            norwegian: "Se alle"
                        ),
                action: {
                    selectTab(.events)
                }
            )

            if let event =
                nextGroupEvent {
                NavigationLink {
                    CommunityGroupEventDetailView(
                        group: currentGroup,
                        event: event
                    )
                } label: {
                    referenceComingEventCard(
                        event
                    )
                }
                .buttonStyle(.plain)
            } else if let challenge =
                        referenceSecondaryChallenge {
                NavigationLink {
                    CommunityGroupChallengeDetailView(
                        group: currentGroup,
                        challenge: challenge
                    )
                } label: {
                    referenceUpcomingChallengeRow(
                        challenge
                    )
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 10) {
                    Image(
                        systemName:
                            "calendar.badge.plus"
                    )
                    .foregroundStyle(
                        clubForest
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "No upcoming events or challenges yet.",
                            norwegian:
                                "Ingen kommende events eller challenges ennå."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )

                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
        .padding(13)
        .background(
            Color.white.opacity(0.94),
            in:
                RoundedRectangle(
                    cornerRadius: 21,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 21,
                style: .continuous
            )
            .stroke(
                Color.black.opacity(0.04),
                lineWidth: 0.7
            )
        }
    }

    private var referenceSecondaryChallenge:
        CommunityGroupChallengeRecord? {
        guard let challenge =
            nextGroupChallenge
        else {
            return nil
        }

        if challenge.id ==
            featuredClubChallenge?.id {
            return nil
        }

        return challenge
    }

    private func referenceComingEventCard(
        _ event:
            CommunityGroupEventRecord
    ) -> some View {
        let displayStart =
            event.nextOccurrenceStart() ??
            event.startsAt

        return HStack(spacing: 10) {
            referenceEventArtwork(event)
                .frame(
                    width: 118,
                    height: 72
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 13,
                        style: .continuous
                    )
                )

            VStack(
                alignment: .leading,
                spacing: 4
            ) {
                Text(
                    ATHLTHLocalization.choose(
                        english: "EVENT",
                        norwegian: "EVENT"
                    )
                )
                .font(
                    .system(
                        size: 9,
                        weight: .bold
                    )
                )
                .foregroundStyle(
                    clubForest
                )
                .padding(
                    .horizontal,
                    8
                )
                .padding(.vertical, 3)
                .background(
                    clubMint,
                    in: Capsule()
                )

                Text(event.title)
                    .font(
                        .subheadline
                            .weight(
                                .bold
                            )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                    .lineLimit(1)

                Label(
                    displayStart.formatted(
                        date: .abbreviated,
                        time: .shortened
                    ),
                    systemImage:
                        "calendar"
                )
                .font(.caption2)
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )

                if !event.meetingName
                    .isEmpty {
                    Label(
                        event.meetingName,
                        systemImage:
                            "location.fill"
                    )
                    .font(.caption2)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                    .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            Image(
                systemName:
                    "chevron.right"
            )
            .font(.caption.bold())
            .foregroundStyle(
                clubForest
            )
            .frame(
                width: 34,
                height: 34
            )
            .background(
                clubMint,
                in: Circle()
            )
        }
        .padding(8)
        .background(
            Color.white.opacity(0.86),
            in:
                RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
        )
    }

    @ViewBuilder
    private func referenceEventArtwork(
        _ event:
            CommunityGroupEventRecord
    ) -> some View {
        ATHLTHArtworkImage(
            reference:
                event.imageURL,
            fallbackAssetName:
                "CommunityHero"
        )
        .athlthBoundedFill()
    }

    private func referenceUpcomingChallengeRow(
        _ challenge:
            CommunityGroupChallengeRecord
    ) -> some View {
        HStack(spacing: 11) {
            Image(
                systemName:
                    "trophy.fill"
            )
            .font(.title3)
            .foregroundStyle(clubLeaf)
            .frame(
                width: 46,
                height: 46
            )
            .background(
                clubLeaf
                    .opacity(0.10),
                in:
                    RoundedRectangle(
                        cornerRadius: 13,
                        style: .continuous
                    )
            )

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(challenge.title)
                    .font(
                        .subheadline
                            .weight(
                                .semibold
                            )
                    )
                    .lineLimit(1)

                Text(
                    comingUpChallengeDetail(
                        challenge
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
                .lineLimit(1)
            }

            Spacer()

            Image(
                systemName:
                    "chevron.right"
            )
            .font(.caption.bold())
            .foregroundStyle(
                .tertiary
            )
        }
        .padding(.vertical, 6)
    }

    private var referenceClubPostsSection:
        some View {
        let pinned =
            groups.pinnedAnnouncement(
                in: group.id
            )

        let remaining =
            groups.announcements(
                in: group.id
            )
            .filter {
                $0.id != pinned?.id
            }

        let ordered =
            ([pinned].compactMap { $0 }) +
            remaining

        let visiblePosts =
            showAllClubPosts
                ? ordered
                : Array(ordered.prefix(2))

        return VStack(spacing: 9) {
            referenceClubSectionHeader(
                icon:
                    "rectangle.and.pencil.and.ellipsis",
                title:
                    ATHLTHLocalization
                        .choose(
                            english:
                                "Recent posts",
                            norwegian:
                                "Nylige innlegg"
                        ),
                subtitle:
                    ATHLTHLocalization.choose(
                        english:
                            "See what is happening in \(currentGroup.name)",
                        norwegian:
                            "Se hva som skjer i \(currentGroup.name)"
                    ),
                actionTitle:
                    ordered.count > 2
                        ? (
                            showAllClubPosts
                                ? ATHLTHLocalization.choose(
                                    english:
                                        "Show less",
                                    norwegian:
                                        "Vis færre"
                                )
                                : ATHLTHLocalization.choose(
                                    english:
                                        "See all",
                                    norwegian:
                                        "Se alle"
                                )
                        )
                        : nil,
                action: {
                    withAnimation(
                        .easeInOut(
                            duration: 0.18
                        )
                    ) {
                        showAllClubPosts.toggle()
                    }
                }
            )

            if visiblePosts.isEmpty {
                HStack(spacing: 10) {
                    Image(
                        systemName:
                            "text.bubble"
                    )
                    .foregroundStyle(
                        clubForest
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "No Club posts yet.",
                            norwegian:
                                "Ingen Club-innlegg ennå."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )

                    Spacer()
                }
                .padding(.vertical, 8)
            } else {
                ForEach(visiblePosts) {
                    update in
                    referenceGroupPostCard(
                        update,
                        isPinned:
                            update.id ==
                            pinned?.id
                    )
                }
            }
        }
        .padding(13)
        .background(
            Color.white.opacity(0.94),
            in:
                RoundedRectangle(
                    cornerRadius: 21,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 21,
                style: .continuous
            )
            .stroke(
                Color.black.opacity(0.04),
                lineWidth: 0.7
            )
        }
    }

    private func referenceClubSectionHeader(
        icon: String,
        title: String,
        subtitle: String,
        actionTitle: String?,
        action: @escaping () -> Void
    ) -> some View {
        HStack(
            alignment: .center,
            spacing: 10
        ) {
            Image(systemName: icon)
                .font(
                    .system(
                        size: 14,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    clubForest
                )
                .frame(
                    width: 36,
                    height: 36
                )
                .background(
                    clubMint,
                    in:
                        RoundedRectangle(
                            cornerRadius: 11,
                            style: .continuous
                        )
                )

            VStack(
                alignment: .leading,
                spacing: 1
            ) {
                Text(title)
                    .font(
                        .headline.weight(
                            .bold
                        )
                    )

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if let actionTitle {
                Button(action: action) {
                    HStack(spacing: 4) {
                        Text(actionTitle)
                        Image(
                            systemName:
                                "chevron.right"
                        )
                    }
                    .font(
                        .caption.weight(
                            .semibold
                        )
                    )
                    .foregroundStyle(
                        clubForest
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func referenceGroupPostCard(
        _ update:
            CommunityGroupAnnouncementRecord,
        isPinned: Bool
    ) -> some View {
        let likeCount =
            groups.announcementLikeCount(
                update.id,
                in: group.id
            )
        let liked =
            groups.hasLikedAnnouncement(
                update.id,
                in: group.id
            )
        let author =
            groups.profileCard(
                for: update.authorID
            )

        return VStack(
            alignment: .leading,
            spacing: 9
        ) {
            HStack(spacing: 9) {
                if let author {
                    CommunityGroupProfileAvatar(
                        profile: author,
                        size: 39
                    )
                } else {
                    Circle()
                        .fill(
                            clubMint
                        )
                        .frame(
                            width: 39,
                            height: 39
                        )
                        .overlay {
                            Image(
                                systemName:
                                    "person.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(
                                clubForest
                            )
                        }
                }

                VStack(
                    alignment: .leading,
                    spacing: 1
                ) {
                    HStack(spacing: 5) {
                        Text(
                            author?
                                .resolvedName ??
                            ATHLTHLocalization
                                .choose(
                                    english:
                                        "Club member",
                                    norwegian:
                                        "Club-medlem"
                                )
                        )
                        .font(
                            .subheadline
                                .weight(
                                    .bold
                                )
                        )
                        .lineLimit(1)

                        if isPinned {
                            Image(
                                systemName:
                                    "pin.fill"
                            )
                            .font(
                                .caption2
                            )
                            .foregroundStyle(
                                clubForest
                            )
                        }
                    }

                    Text(
                        update.createdAt,
                        style: .relative
                    )
                    .font(.caption2)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                }

                Spacer()

                if groups.canPublishUpdates(
                    currentGroup
                ) {
                    Menu {
                        Button {
                            Task {
                                _ =
                                    await groups
                                        .pinAnnouncement(
                                            groupID:
                                                group.id,
                                            announcementID:
                                                isPinned
                                                    ? nil
                                                    : update.id
                                        )
                            }
                        } label: {
                            Label(
                                isPinned
                                    ? ATHLTHLocalization
                                        .choose(
                                            english:
                                                "Unpin",
                                            norwegian:
                                                "Fjern festing"
                                        )
                                    : ATHLTHLocalization
                                        .choose(
                                            english:
                                                "Pin post",
                                            norwegian:
                                                "Fest innlegg"
                                        ),
                                systemImage:
                                    isPinned
                                        ? "pin.slash"
                                        : "pin"
                            )
                        }

                        if groups.canManage(
                            currentGroup
                        ) {
                            Button(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Delete post",
                                    norwegian:
                                        "Slett innlegg"
                                ),
                                role: .destructive
                            ) {
                                Task {
                                    _ =
                                        await groups
                                            .deleteAnnouncement(
                                                groupID:
                                                    group.id,
                                                announcementID:
                                                    update.id
                                            )
                                }
                            }
                        }
                    } label: {
                        Image(
                            systemName:
                                "ellipsis"
                        )
                        .font(.headline)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                        .frame(
                            width: 30,
                            height: 30
                        )
                    }
                }
            }

            Text(update.body)
                .font(.subheadline)
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )

            HStack {
                Spacer()

                Button {
                    Task {
                        _ =
                            await groups
                                .toggleAnnouncementLike(
                                    groupID:
                                        group.id,
                                    announcementID:
                                        update.id
                                )
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(
                            systemName:
                                liked
                                    ? "heart.fill"
                                    : "heart"
                        )
                        if likeCount > 0 {
                            Text(
                                "\(likeCount)"
                            )
                            .monospacedDigit()
                        }
                    }
                    .font(
                        .caption.weight(
                            .semibold
                        )
                    )
                    .foregroundStyle(
                        liked
                            ? Color.red
                            : ATHLTHTheme
                                .mutedText
                    )
                    .padding(
                        .horizontal,
                        11
                    )
                    .frame(height: 32)
                    .background(
                        Color.white,
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .stroke(
                                Color.black
                                    .opacity(
                                        0.04
                                    ),
                                lineWidth:
                                    0.7
                            )
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(11)
        .background(
            Color.white.opacity(0.92),
            in:
                RoundedRectangle(
                    cornerRadius: 17,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 17,
                style: .continuous
            )
            .stroke(
                Color.black.opacity(0.04),
                lineWidth: 0.7
            )
        }
    }

    private var featuredClubChallenge:
        CommunityGroupChallengeRecord? {
        guard
            let featuredID =
                currentGroup.featuredChallengeID,
            let challenge =
                groups.challenges(in: group.id)
                    .first(
                        where: {
                            $0.id == featuredID
                        }
                    ),
            challenge.status != "draft",
            challenge.status != "cancelled",
            challenge.endsAt >= Date()
        else {
            return nil
        }

        return challenge
    }

    private func clubChallengeCard(
        _ challenge:
            CommunityGroupChallengeRecord
    ) -> some View {
        NavigationLink {
            CommunityGroupChallengeDetailView(
                group: currentGroup,
                challenge: challenge
            )
        } label: {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(
                    cornerRadius: 24,
                    style: .continuous
                )
                .fill(
                    LinearGradient(
                        colors: [
                            clubForest,
                            clubEmerald,
                            clubLeaf
                                .opacity(0.92)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

                if challenge.imageURL != nil {
                    ATHLTHArtworkImage(
                        reference:
                            challenge.imageURL,
                        fallbackAssetName:
                            "CommunityHero"
                    )
                    .opacity(0.38)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 24,
                            style: .continuous
                        )
                    )
                }

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.06),
                        Color.black.opacity(0.58)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 24,
                        style: .continuous
                    )
                )

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Label(
                            "CLUB CHALLENGE",
                            systemImage: "trophy.fill"
                        )
                        .font(.caption2.weight(.bold))
                        .tracking(0.7)
                        .foregroundStyle(
                            ATHLTHTheme.champagne
                        )

                        Spacer()

                        Text(
                            challenge.startsAt <= Date()
                                ? "ACTIVE"
                                : "UP NEXT"
                        )
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            Color.white.opacity(0.14),
                            in: Capsule()
                        )
                    }

                    Text(challenge.title)
                        .font(
                            .title2
                                .weight(.bold)
                        )
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    if !challenge.summary.isEmpty {
                        Text(challenge.summary)
                            .font(.subheadline)
                            .foregroundStyle(
                                .white.opacity(0.82)
                            )
                            .lineLimit(2)
                    }

                    HStack {
                        Text(
                            comingUpChallengeDetail(
                                challenge
                            )
                        )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(
                            .white.opacity(0.76)
                        )
                        .lineLimit(1)

                        Spacer()

                        Label(
                            "Open",
                            systemImage:
                                "arrow.right"
                        )
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                    }
                }
                .padding(18)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 184)
            .clipped()
            .overlay {
                RoundedRectangle(
                    cornerRadius: 24,
                    style: .continuous
                )
                .stroke(
                    Color.white.opacity(0.12),
                    lineWidth: 1
                )
            }
            .shadow(
                color:
                    clubForest
                        .opacity(0.15),
                radius: 18,
                y: 9
            )
        }
        .buttonStyle(.plain)
    }

    private var clubLeaderboardCard: some View {
        let entries = groups.leaderboard(
            in: group.id
        )

        return ATHLTHCard {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "Club Leaderboard",
                            norwegian: "Club Leaderboard"
                        )
                    )
                    .font(.title3.weight(.bold))

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Last 7 days · training, participation and Club activity.",
                            norwegian:
                                "Siste 7 dager · trening, deltakelse og aktivitet i Club-en."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if entries.isEmpty {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Leaderboard activity will appear as members train and take part in the Club.",
                        norwegian:
                            "Leaderboard fylles når medlemmer trener og deltar i Club-en."
                    )
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(
                        Array(
                            entries
                                .prefix(5)
                                .enumerated()
                        ),
                        id: \.element.id
                    ) { index, entry in
                        HStack(spacing: 11) {
                            Text("\(index + 1)")
                                .font(
                                    .caption
                                        .weight(.bold)
                                )
                                .frame(
                                    width: 30,
                                    height: 30
                                )
                                .background(
                                    index < 3
                                        ? clubEmerald
                                            .opacity(0.14)
                                        : Color.secondary
                                            .opacity(0.08),
                                    in: Circle()
                                )

                            VStack(
                                alignment: .leading,
                                spacing: 3
                            ) {
                                HStack(spacing: 6) {
                                    Text(
                                        leaderboardDisplayName(
                                            for: entry.userID
                                        )
                                    )
                                    .font(
                                        .subheadline
                                            .weight(.semibold)
                                    )

                                    if entry.userID ==
                                        session.profile.userID {
                                        Text("You")
                                            .font(
                                                .caption2
                                                    .weight(.bold)
                                            )
                                            .foregroundStyle(
                                                clubForest
                                            )
                                    }
                                }

                                Text(
                                    leaderboardActivitySummary(
                                        entry
                                    )
                                )
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            }

                            Spacer(minLength: 8)

                            Text(
                                ATHLTHLocalization.format(
                            english: "%d pts",
                            norwegian: "%d poeng",
                            entry.score
                        )
                            )
                            .font(
                                .subheadline
                                    .weight(.bold)
                            )
                            .foregroundStyle(
                                clubForest
                            )
                        }
                        .padding(.vertical, 9)

                        if entry.id !=
                            entries.prefix(5).last?.id {
                            Divider()
                                .padding(.leading, 41)
                        }
                    }
                }
                .padding(.top, 8)
            }

            Text(
                ATHLTHLocalization.choose(
                    english:
                        "Scoring: workouts, events and challenges +5. Chat and likes +1, capped at 5 per day each.",
                    norwegian:
                        "Poeng: økter, events og challenges +5. Chat og likes +1, maks 5 per dag hver."
                )
            )
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.top, 10)
        }
    }

    private func leaderboardDisplayName(
        for userID: UUID
    ) -> String {
        guard let profile = groups.profileCard(
            for: userID
        ) else {
            return "Club member"
        }

        return profile.usernameLabel.isEmpty
            ? profile.resolvedName
            : profile.usernameLabel
    }

    private func leaderboardActivitySummary(
        _ entry: CommunityGroupEngagementLeaderboardEntry
    ) -> String {
        var parts: [String] = []

        if entry.workoutCount > 0 {
            parts.append(
                "\(entry.workoutCount) workout" +
                (entry.workoutCount == 1 ? "" : "s")
            )
        }

        if entry.messageCount > 0 {
            parts.append(
                "\(entry.messageCount) chat"
            )
        }

        if entry.likesGiven > 0 {
            parts.append(
                "\(entry.likesGiven) like" +
                (entry.likesGiven == 1 ? "" : "s")
            )
        }

        if entry.eventsJoined > 0 {
            parts.append(
                "\(entry.eventsJoined) event" +
                (entry.eventsJoined == 1 ? "" : "s")
            )
        }

        if entry.challengesJoined > 0 {
            parts.append(
                "\(entry.challengesJoined) challenge" +
                (entry.challengesJoined == 1
                    ? ""
                    : "s")
            )
        }

        return parts.isEmpty
            ? "No activity yet"
            : parts.joined(separator: " · ")
    }

    private var groupUpdateComposer: some View {
        ATHLTHCard {
            HStack(spacing: 9) {
                Image(systemName: "megaphone.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(clubForest)
                    .frame(width: 34, height: 34)
                    .background(
                        clubMint,
                        in: RoundedRectangle(
                            cornerRadius: 11,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Club Post")
                        .font(.subheadline.weight(.semibold))
                    Text("Visible to every Club member")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField(
                    "Share a Club post…",
                    text: $updateDraft,
                    axis: .vertical
                )
                .lineLimit(1...5)
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .background(
                    Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(
                        cornerRadius: 15,
                        style: .continuous
                    )
                )

                Button {
                    let body = updateDraft
                    updateDraft = ""

                    Task {
                        postingUpdate = true
                        let posted = await groups.postAnnouncement(
                            groupID: group.id,
                            body: body
                        )
                        postingUpdate = false

                        if !posted {
                            updateDraft = body
                        }
                    }
                } label: {
                    Group {
                        if postingUpdate {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 15, weight: .bold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(
                        clubForest,
                        in: Circle()
                    )
                }
                .disabled(
                    updateDraft.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty ||
                    updateDraft.count > 1200 ||
                    postingUpdate
                )
            }
            .padding(.top, 12)
        }
    }

    private var nextGroupEvent: CommunityGroupEventRecord? {
        let now = Date()

        return groups.events(in: group.id)
            .filter {
                $0.status != "draft" &&
                $0.status != "cancelled" &&
                $0.nextOccurrenceStart(
                    relativeTo: now
                ) != nil
            }
            .sorted {
                ($0.nextOccurrenceStart(
                    relativeTo: now
                ) ?? .distantFuture) <
                ($1.nextOccurrenceStart(
                    relativeTo: now
                ) ?? .distantFuture)
            }
            .first
    }

    private var nextGroupChallenge: CommunityGroupChallengeRecord? {
        let now = Date()

        return groups.challenges(in: group.id)
            .filter {
                $0.endsAt >= now &&
                $0.status != "draft" &&
                $0.status != "cancelled"
            }
            .sorted { lhs, rhs in
                let lhsActive =
                    lhs.startsAt <= now && lhs.endsAt >= now
                let rhsActive =
                    rhs.startsAt <= now && rhs.endsAt >= now

                if lhsActive != rhsActive {
                    return lhsActive
                }

                return lhs.startsAt < rhs.startsAt
            }
            .first
    }

    private var comingUpCard: some View {
        ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Coming Up")
                        .font(.title3.weight(.bold))
                    Text("The next things happening in this Club.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if nextGroupEvent == nil &&
                nextGroupChallenge == nil {
                Text("No upcoming events or challenges yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 14)
            } else {
                VStack(spacing: 0) {
                    if let event = nextGroupEvent {
                        NavigationLink {
                            CommunityGroupEventDetailView(
                                group: currentGroup,
                                event: event
                            )
                        } label: {
                            comingUpRow(
                                icon: "calendar",
                                title: event.title,
                                detail:
                                    comingUpEventDetail(event),
                                tint: ATHLTHTheme.recoveryBlue
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if nextGroupEvent != nil &&
                        nextGroupChallenge != nil {
                        Divider()
                            .padding(.leading, 46)
                    }

                    if let challenge = nextGroupChallenge {
                        NavigationLink {
                            CommunityGroupChallengeDetailView(
                                group: currentGroup,
                                challenge: challenge
                            )
                        } label: {
                            comingUpRow(
                                icon: "bolt.fill",
                                title: challenge.title,
                                detail:
                                    comingUpChallengeDetail(
                                        challenge
                                    ),
                                tint: clubLeaf
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private func comingUpEventDetail(
        _ event: CommunityGroupEventRecord
    ) -> String {
        let nextStart =
            event.nextOccurrenceStart()
            ?? event.startsAt

        var parts = [
            nextStart.formatted(
                date: .abbreviated,
                time: .shortened
            ),
            event.meetingName
        ]

        let going = groups.eventRSVPCount(
            eventID: event.id,
            status: "going"
        )

        if going > 0 {
            parts.append("\(going) going")
        }

        return parts
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private func comingUpChallengeDetail(
        _ challenge: CommunityGroupChallengeRecord
    ) -> String {
        let timing =
            challenge.startsAt <= Date()
                ? "Active now · ends " +
                    challenge.endsAt.formatted(
                        date: .abbreviated,
                        time: .omitted
                    )
                : "Starts " +
                    challenge.startsAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )

        guard challenge.targetValue > 0 else {
            return timing
        }

        let progress = groups.challengeProgress(
            challenge
        )
        let fraction = min(
            max(
                progress / challenge.targetValue,
                0
            ),
            1
        )

        return timing +
            " · " +
            String(
                format: "%.0f%% complete",
                fraction * 100
            )
    }

    private var recentGroupActivityCard: some View {
        let items = Array(
            groups.activity(in: group.id)
                .filter { $0.kind != "announcement" }
                .prefix(4)
        )

        return ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recent Activity")
                        .font(.title3.weight(.bold))
                    Text(
                        "What has changed in the Club lately."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if items.isEmpty {
                Text(
                    "New members, events and challenges will appear here."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        recentActivityRow(item)

                        if item.id != items.last?.id {
                            Divider()
                                .padding(.leading, 46)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private func recentActivityRow(
        _ item: CommunityGroupActivityRecord
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(
                systemName:
                    recentActivityIcon(item.kind)
            )
            .font(
                .system(
                    size: 14,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                recentActivityTint(item.kind)
            )
            .frame(width: 34, height: 34)
            .background(
                recentActivityTint(item.kind)
                    .opacity(0.10),
                in: RoundedRectangle(
                    cornerRadius: 11,
                    style: .continuous
                )
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(item.headline)
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )

                if let detail = item.detail,
                   !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 5) {
                    if let actorID = item.actorID,
                       let actor = groups.profileCard(
                           for: actorID
                       ) {
                        Text(
                            actor.usernameLabel.isEmpty
                                ? actor.resolvedName
                                : actor.usernameLabel
                        )
                    }

                    Text(
                        item.createdAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(.vertical, 9)
    }

    private func recentActivityIcon(
        _ kind: String
    ) -> String {
        switch kind {
        case "member_joined":
            return "person.badge.plus"
        case "announcement":
            return "megaphone.fill"
        case "event_created":
            return "calendar.badge.plus"
        case "challenge_created":
            return "bolt.fill"
        default:
            return "bell.fill"
        }
    }

    private func recentActivityTint(
        _ kind: String
    ) -> Color {
        switch kind {
        case "member_joined":
            return clubEmerald
        case "announcement":
            return clubLeaf
        case "event_created":
            return ATHLTHTheme.recoveryBlue
        case "challenge_created":
            return .green
        default:
            return clubEmerald
        }
    }

    private func comingUpRow(
        icon: String,
        title: String,
        detail: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(
                    tint.opacity(0.10),
                    in: RoundedRectangle(
                        cornerRadius: 11,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .lineLimit(1)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 9)
    }

    private func groupUpdateCard(
        _ update: CommunityGroupAnnouncementRecord,
        isPinned: Bool = false
    ) -> some View {
        let likeCount = groups.announcementLikeCount(
            update.id,
            in: group.id
        )
        let liked = groups.hasLikedAnnouncement(
            update.id,
            in: group.id
        )

        return ATHLTHCard {
            HStack {
                Label(
                    isPinned
                        ? "Pinned Post"
                        : "Club Post",
                    systemImage:
                        isPinned
                            ? "pin.fill"
                            : "megaphone.fill"
                )
                .font(.headline)
                .foregroundStyle(
                    isPinned
                        ? clubForest
                        : clubForest
                )

                Spacer()

                if groups.canPublishUpdates(currentGroup) {
                    Menu {
                        Button {
                            Task {
                                _ = await groups.pinAnnouncement(
                                    groupID: group.id,
                                    announcementID:
                                        isPinned
                                            ? nil
                                            : update.id
                                )
                            }
                        } label: {
                            Label(
                                isPinned
                                    ? "Unpin Post"
                                    : "Pin Post",
                                systemImage:
                                    isPinned
                                        ? "pin.slash"
                                        : "pin"
                            )
                        }

                        if groups.canManage(currentGroup) {
                            Button(
                                "Delete Post",
                                role: .destructive
                            ) {
                                Task {
                                    _ = await groups.deleteAnnouncement(
                                        groupID: group.id,
                                        announcementID: update.id
                                    )
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 30, height: 30)
                    }
                }

                Text(
                    update.createdAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Text(update.body)
                .font(.subheadline)
                .foregroundStyle(ATHLTHTheme.primaryText)
                .padding(.top, 6)

            if let author = groups.profileCard(
                for: update.authorID
            ) {
                Text(
                    author.username
                        .flatMap { value in
                            let clean = value.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                            return clean.isEmpty
                                ? nil
                                : "Posted by @\(clean)"
                        }
                        ?? "Posted by \(author.resolvedName)"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }

            Button {
                Task {
                    _ = await groups
                        .toggleAnnouncementLike(
                            groupID: group.id,
                            announcementID: update.id
                        )
                }
            } label: {
                Label(
                    likeCount == 0
                        ? "Like"
                        : "\(likeCount)",
                    systemImage:
                        liked
                            ? "hand.thumbsup.fill"
                            : "hand.thumbsup"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    liked
                        ? clubForest
                        : .secondary
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    liked
                        ? clubEmerald
                            .opacity(0.12)
                        : Color.secondary
                            .opacity(0.07),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                liked
                    ? "Remove thumbs up"
                    : "Give thumbs up"
            )
            .padding(.top, 9)
        }
    }

    private var chat: some View {
        VStack(spacing: 0) {
            let messages = groups.messages(
                in: group.id
            )

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if messages.isEmpty {
                            ContentUnavailableView(
                                "No messages yet",
                                systemImage:
                                    "bubble.left.and.bubble.right",
                                description: Text(
                                    "Start the Club conversation."
                                )
                            )
                            .padding(.top, 70)
                        } else {
                            ForEach(messages) { message in
                                messageRow(message)
                                    .id(message.id)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
                .defaultScrollAnchor(.bottom)
                .background(
                    ATHLTHTheme.cardWarm.opacity(0.36)
                )
                .frame(maxHeight: .infinity)
                .onChange(
                    of: messages.count
                ) { _, _ in
                    guard let last = messages.last else {
                        return
                    }

                    withAnimation(
                        .easeOut(duration: 0.18)
                    ) {
                        proxy.scrollTo(
                            last.id,
                            anchor: .bottom
                        )
                    }
                }
                .task {
                    guard let last = messages.last else {
                        return
                    }

                    proxy.scrollTo(
                        last.id,
                        anchor: .bottom
                    )
                }
            }

            if !groupMentionSuggestions.isEmpty {
                ATHLTHMentionSuggestionList(
                    suggestions:
                        groupMentionSuggestions
                ) { suggestion in
                    messageDraft =
                        ATHLTHMentionSupport.inserting(
                            suggestion,
                            into: messageDraft
                        )
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .background(.ultraThinMaterial)
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField(
                    "Message Club",
                    text: $messageDraft,
                    axis: .vertical
                )
                .lineLimit(1...4)
                .submitLabel(.send)
                .onSubmit {
                    Task {
                        await sendGroupMessage()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Color.white.opacity(0.86),
                    in: RoundedRectangle(
                        cornerRadius: 18,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 18,
                        style: .continuous
                    )
                    .stroke(
                        clubEmerald
                            .opacity(0.16),
                        lineWidth: 1
                    )
                }
                .frame(maxWidth: .infinity)

                Button {
                    Task {
                        await sendGroupMessage()
                    }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(
                            .system(
                                size: 16,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(
                            LinearGradient(
                                colors: [
                                    clubForest,
                                    clubEmerald
                                ],
                                startPoint:
                                    .topLeading,
                                endPoint:
                                    .bottomTrailing
                            ),
                            in: Circle()
                        )
                }
                .disabled(
                    messageDraft
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        .isEmpty
                )
            }
            .padding(.horizontal, 14)
            .padding(.top, 9)
            .padding(.bottom, 8)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Divider()
                    .opacity(0.55)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: selectedTab) {
            guard selectedTab == .chat else {
                return
            }

            while !Task.isCancelled {
                await groups.refreshMessages(
                    group.id
                )
                try? await Task.sleep(
                    for: .seconds(5)
                )
            }
        }
    }

    private func sendGroupMessage() async {
        let body = messageDraft
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !body.isEmpty else {
            return
        }

        messageDraft = ""

        let sent = await groups.sendMessage(
            groupID: group.id,
            senderName:
                session.profile.username.isEmpty
                    ? session.profile.displayName
                    : "@\(session.profile.username)",
            body: body
        )

        if !sent {
            messageDraft = body
        }
    }

    private var groupMentionSuggestions:
        [ATHLTHMentionSuggestion] {
        let candidates = groups.mentionCandidates(
            in: group.id
        ).filter {
            $0.userID != session.profile.userID
        }

        let role = groups.role(in: currentGroup)

        return ATHLTHMentionSupport.suggestions(
            in: messageDraft,
            candidates: candidates,
            includeEveryone:
                role == "owner" ||
                role == "admin" ||
                role == "contributor"
        )
    }

    private var visibleGroupEvents:
        [CommunityGroupEventRecord] {
        groups.events(in: group.id).filter {
            event in

            event.status != "draft" ||
            groups.canManage(currentGroup) ||
            event.creatorID ==
                session.profile.userID
        }
    }

    private var events: some View {
        ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Club Events")
                        .font(.title3.weight(.bold))
                    Text(
                        groups.canCreateGroupContent(
                            currentGroup
                        )
                            ? "Plan meetups and training sessions with the group."
                            : "Only members allowed by the group settings can create events."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if groups.canCreateGroupContent(
                    currentGroup
                ) {
                    Button {
                        showingCreateEvent = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.bordered)
                }
            }

            if visibleGroupEvents.isEmpty {
                ContentUnavailableView(
                    "No group events",
                    systemImage: "calendar.badge.plus",
                    description: Text(
                        groups.canCreateGroupContent(
                            currentGroup
                        )
                            ? "Create the first event for this group."
                            : "No events have been scheduled yet."
                    )
                )
                .padding(.vertical, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(
                        visibleGroupEvents
                    ) { event in
                        NavigationLink {
                            CommunityGroupEventDetailView(
                                group: currentGroup,
                                event: event
                            )
                        } label: {
                            VStack(
                                alignment: .leading,
                                spacing: 10
                            ) {
                                if let imageURL =
                                    event.imageURL,
                                   !imageURL.isEmpty {
                                    communityContentCover(
                                        imageURL,
                                        height: 140
                                    )
                                }

                                HStack(spacing: 12) {
                                    Image(
                                        systemName:
                                            eventIcon(
                                                event
                                                    .activityType
                                            )
                                    )
                                    .foregroundStyle(ATHLTHTheme.recoveryBlue)
                                    .frame(
                                        width: 38,
                                        height: 38
                                    )
                                    .background(
                                        ATHLTHTheme.recoveryBlue
                                            .opacity(0.08),
                                        in:
                                            RoundedRectangle(
                                                cornerRadius:
                                                    12
                                            )
                                    )

                                    VStack(
                                        alignment: .leading,
                                        spacing: 2
                                    ) {
                                        HStack(spacing: 7) {
                                            Text(event.title)
                                                .font(
                                                    .subheadline
                                                        .weight(
                                                            .semibold
                                                        )
                                                )

                                            Text(
                                                event
                                                    .resolvedStatus
                                                    .title
                                            )
                                            .font(
                                                .system(
                                                    size: 9,
                                                    weight:
                                                        .bold
                                                )
                                            )
                                            .foregroundStyle(
                                                groupContentStatusColor(
                                                    event
                                                        .resolvedStatus
                                                )
                                            )
                                            .padding(
                                                .horizontal,
                                                6
                                            )
                                            .padding(
                                                .vertical,
                                                3
                                            )
                                            .background(
                                                groupContentStatusColor(
                                                    event
                                                        .resolvedStatus
                                                )
                                                .opacity(
                                                    0.10
                                                ),
                                                in: Capsule()
                                            )
                                        }

                                        Text(
                                            eventDetailText(
                                                event
                                            )
                                        )
                                        .font(.caption)
                                        .foregroundStyle(
                                            .secondary
                                        )

                                        if let configuration =
                                            event
                                                .activityConfiguration {
                                            Text(
                                                configuration
                                                    .compactSummary
                                            )
                                            .font(
                                                .caption
                                                    .weight(
                                                        .semibold
                                                    )
                                            )
                                            .foregroundStyle(
                                                clubForest
                                            )
                                            .lineLimit(2)
                                        }

                                        if !event.summary.isEmpty {
                                            Text(
                                                event.summary
                                            )
                                            .font(.caption)
                                            .foregroundStyle(
                                                .secondary
                                            )
                                            .lineLimit(2)
                                        }
                                    }

                                    Spacer()

                                    Image(
                                        systemName:
                                            "chevron.right"
                                    )
                                    .font(.caption2.bold())
                                    .foregroundStyle(
                                        .tertiary
                                    )
                                }

                                let going =
                                    groups
                                        .eventRSVPCount(
                                            eventID:
                                                event.id,
                                            status:
                                                "going"
                                        )
                                let waitlist =
                                    groups
                                        .eventRSVPCount(
                                            eventID:
                                                event.id,
                                            status:
                                                "waitlist"
                                        )

                                if going > 0 ||
                                    waitlist > 0 ||
                                    event.capacity != nil {
                                    HStack(spacing: 8) {
                                        Label(
                                            event.capacity.map {
                                                "\(going)/\($0) going"
                                            } ??
                                            "\(going) going",
                                            systemImage:
                                                "person.2.fill"
                                        )

                                        if waitlist > 0 {
                                            Text(
                                                ATHLTHLocalization.format(
                                                english: "· %d waitlisted",
                                                norwegian: "· %d på venteliste",
                                                waitlist
                                            )
                                            )
                                        }
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(
                                        .secondary
                                    )
                                }
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)

                        if event.id !=
                            visibleGroupEvents.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private var visibleGroupChallenges:
        [CommunityGroupChallengeRecord] {
        groups.challenges(in: group.id).filter {
            challenge in

            challenge.status != "draft" ||
            groups.canManage(currentGroup) ||
            challenge.creatorID ==
                session.profile.userID
        }
    }

    private var activeGroupChallenges:
        [CommunityGroupChallengeRecord] {
        let now = Date()

        return visibleGroupChallenges
            .filter {
                $0.status != "draft" &&
                $0.status != "cancelled" &&
                $0.startsAt <= now &&
                $0.endsAt >= now
            }
            .sorted {
                $0.endsAt < $1.endsAt
            }
    }

    private var plannedGroupChallenges:
        [CommunityGroupChallengeRecord] {
        let now = Date()

        return visibleGroupChallenges
            .filter {
                $0.status != "draft" &&
                $0.status != "cancelled" &&
                $0.startsAt > now
            }
            .sorted {
                $0.startsAt < $1.startsAt
            }
    }

    private var previousGroupChallenges:
        [CommunityGroupChallengeRecord] {
        let now = Date()

        return visibleGroupChallenges
            .filter {
                $0.status == "cancelled" ||
                $0.endsAt < now
            }
            .sorted {
                $0.endsAt > $1.endsAt
            }
    }

    private var challenges: some View {
        VStack(spacing: 14) {
            ATHLTHCard {
                HStack(spacing: 12) {
                    VStack(
                        alignment: .leading,
                        spacing: 4
                    ) {
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Club Challenges",
                                norwegian:
                                    "Club Challenges"
                            )
                        )
                        .font(
                            .title3.weight(.bold)
                        )

                        Text(
                            groups.canCreateGroupContent(
                                currentGroup
                            )
                                ? ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Run one now or schedule several challenges ahead.",
                                        norwegian:
                                            "Kjør én nå eller planlegg flere challenges fremover."
                                    )
                                : ATHLTHLocalization
                                    .choose(
                                        english:
                                            "See active and planned challenges for the Club.",
                                        norwegian:
                                            "Se aktive og planlagte challenges for Club-en."
                                    )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                    }

                    Spacer()

                    if groups.canCreateGroupContent(
                        currentGroup
                    ) {
                        Button {
                            showingCreateChallenge = true
                        } label: {
                            Image(
                                systemName:
                                    "calendar.badge.plus"
                            )
                            .font(
                                .system(
                                    size: 16,
                                    weight: .semibold
                                )
                            )
                            .foregroundStyle(.white)
                            .frame(
                                width: 40,
                                height: 40
                            )
                            .background(
                                LinearGradient(
                                    colors: [
                                        clubForest,
                                        clubEmerald
                                    ],
                                    startPoint:
                                        .topLeading,
                                    endPoint:
                                        .bottomTrailing
                                ),
                                in: Circle()
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            ATHLTHLocalization.choose(
                                english:
                                    "Plan a Club challenge",
                                norwegian:
                                    "Planlegg Club challenge"
                            )
                        )
                    }
                }

                if groups.canManage(
                    currentGroup
                ) &&
                    !plannedGroupChallenges
                        .isEmpty {
                    HStack(spacing: 8) {
                        Image(
                            systemName:
                                "calendar.circle.fill"
                        )
                        .foregroundStyle(
                            clubEmerald
                        )

                        Text(
                            ATHLTHLocalization.format(
                                english:
                                    plannedGroupChallenges
                                        .count == 1
                                        ? "%d challenge planned ahead"
                                        : "%d challenges planned ahead",
                                norwegian:
                                    plannedGroupChallenges
                                        .count == 1
                                        ? "%d challenge planlagt fremover"
                                        : "%d challenges planlagt fremover",
                                plannedGroupChallenges
                                    .count
                            )
                        )
                        .font(
                            .caption.weight(
                                .semibold
                            )
                        )
                        .foregroundStyle(
                            clubForest
                        )

                        Spacer()
                    }
                    .padding(.top, 4)
                }
            }

            if activeGroupChallenges.isEmpty &&
                plannedGroupChallenges.isEmpty &&
                previousGroupChallenges.isEmpty {
                ATHLTHCard {
                    ContentUnavailableView(
                        ATHLTHLocalization.choose(
                            english:
                                "No Club challenges yet",
                            norwegian:
                                "Ingen Club challenges ennå"
                        ),
                        systemImage:
                            "calendar.badge.plus",
                        description:
                            Text(
                                groups
                                    .canCreateGroupContent(
                                        currentGroup
                                    )
                                    ? ATHLTHLocalization
                                        .choose(
                                            english:
                                                "Create one now or schedule a future challenge from a Club template.",
                                            norwegian:
                                                "Opprett en nå eller planlegg en fremtidig challenge fra en Club-mal."
                                        )
                                    : ATHLTHLocalization
                                        .choose(
                                            english:
                                                "No challenges have been scheduled yet.",
                                            norwegian:
                                                "Ingen challenges er planlagt ennå."
                                        )
                            )
                    )
                    .padding(.vertical, 18)
                }
            }

            if !activeGroupChallenges.isEmpty {
                challengeScheduleSection(
                    title:
                        ATHLTHLocalization.choose(
                            english: "Active now",
                            norwegian: "Aktive nå"
                        ),
                    subtitle:
                        ATHLTHLocalization.choose(
                            english:
                                "Challenges currently counting workouts.",
                            norwegian:
                                "Challenges som teller økter akkurat nå."
                        ),
                    icon: "bolt.fill",
                    challenges:
                        activeGroupChallenges,
                    planned: false
                )
            }

            if !plannedGroupChallenges.isEmpty {
                challengeScheduleSection(
                    title:
                        ATHLTHLocalization.choose(
                            english: "Planned",
                            norwegian: "Planlagte"
                        ),
                    subtitle:
                        ATHLTHLocalization.choose(
                            english:
                                "Upcoming challenges in the Club schedule.",
                            norwegian:
                                "Kommende challenges i Club-planen."
                        ),
                    icon:
                        "calendar.badge.clock",
                    challenges:
                        plannedGroupChallenges,
                    planned: true
                )
            }

            if !previousGroupChallenges.isEmpty {
                challengeScheduleSection(
                    title:
                        ATHLTHLocalization.choose(
                            english: "Previous",
                            norwegian: "Tidligere"
                        ),
                    subtitle:
                        ATHLTHLocalization.choose(
                            english:
                                "Recently completed or cancelled challenges.",
                            norwegian:
                                "Nylig fullførte eller avlyste challenges."
                        ),
                    icon:
                        "clock.arrow.circlepath",
                    challenges:
                        Array(
                            previousGroupChallenges
                                .prefix(4)
                        ),
                    planned: false
                )
            }
        }
    }

    private func challengeScheduleSection(
        title: String,
        subtitle: String,
        icon: String,
        challenges:
            [CommunityGroupChallengeRecord],
        planned: Bool
    ) -> some View {
        ATHLTHCard {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(
                        .system(
                            size: 15,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        planned
                            ? clubEmerald
                            : clubForest
                    )
                    .frame(
                        width: 34,
                        height: 34
                    )
                    .background(
                        (
                            planned
                                ? clubMint
                                : clubMint
                        ),
                        in:
                            RoundedRectangle(
                                cornerRadius: 10,
                                style: .continuous
                            )
                    )

                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text(title)
                        .font(
                            .headline.weight(
                                .bold
                            )
                        )

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                }

                Spacer()

                Text(
                    String(
                        challenges.count
                    )
                )
                .font(
                    .caption.weight(
                        .bold
                    )
                )
                .foregroundStyle(
                    clubForest
                )
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    clubMint.opacity(0.72),
                    in: Capsule()
                )
            }

            VStack(spacing: 10) {
                ForEach(challenges) {
                    challenge in
                    NavigationLink {
                        CommunityGroupChallengeDetailView(
                            group:
                                currentGroup,
                            challenge:
                                challenge
                        )
                    } label: {
                        if planned {
                            plannedGroupChallengeCard(
                                challenge
                            )
                        } else {
                            groupChallengeCard(
                                challenge
                            )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 8)
        }
    }

    private func plannedGroupChallengeCard(
        _ challenge:
            CommunityGroupChallengeRecord
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
                .fill(
                    LinearGradient(
                        colors: [
                            clubForest,
                            clubEmerald
                        ],
                        startPoint:
                            .topLeading,
                        endPoint:
                            .bottomTrailing
                    )
                )

                Image(
                    systemName:
                        challenge.metric.icon
                )
                .font(
                    .system(
                        size: 20,
                        weight: .semibold
                    )
                )
                .foregroundStyle(.white)
            }
            .frame(width: 52, height: 52)

            VStack(
                alignment: .leading,
                spacing: 4
            ) {
                HStack(spacing: 7) {
                    Text(challenge.title)
                        .font(
                            .subheadline
                                .weight(
                                    .bold
                                )
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .primaryText
                        )
                        .lineLimit(1)

                    Text(
                        ATHLTHLocalization.choose(
                            english: "PLANNED",
                            norwegian: "PLANLAGT"
                        )
                    )
                    .font(
                        .system(
                            size: 8,
                            weight: .bold
                        )
                    )
                    .tracking(0.6)
                    .foregroundStyle(
                        clubForest
                    )
                    .padding(
                        .horizontal,
                        6
                    )
                    .padding(
                        .vertical,
                        3
                    )
                    .background(
                        clubMint,
                        in: Capsule()
                    )
                }

                Text(
                    challenge.startsAt
                        .formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                )
                .font(
                    .caption.weight(
                        .semibold
                    )
                )
                .foregroundStyle(
                    clubForest
                )

                Text(
                    ATHLTHLocalization.format(
                        english:
                            "Ends %@",
                        norwegian:
                            "Slutter %@",
                        challenge.endsAt
                            .formatted(
                                date:
                                    .abbreviated,
                                time:
                                    .omitted
                            )
                    )
                )
                .font(.caption2)
                .foregroundStyle(
                    .secondary
                )
            }

            Spacer()

            Image(
                systemName:
                    "chevron.right"
            )
            .font(.caption.bold())
            .foregroundStyle(
                .tertiary
            )
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [
                    ATHLTHTheme.card,
                    clubMint.opacity(0.72)
                ],
                startPoint:
                    .topLeading,
                endPoint:
                    .bottomTrailing
            ),
            in:
                RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
            .stroke(
                clubEmerald
                    .opacity(0.14),
                lineWidth: 0.8
            )
        }
    }

    private func overviewMetric(
        icon: String,
        value: String,
        title: String
    ) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .foregroundStyle(clubForest)
            Text(value)
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            Color.primary.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 13)
        )
    }

    private func messageRow(
        _ message: CommunityGroupMessageRecord
    ) -> some View {
        let mine =
            message.senderID ==
            session.profile.userID
        let profile = groups.profileCard(
            for: message.senderID
        )

        return HStack(
            alignment: .bottom,
            spacing: 8
        ) {
            if !mine {
                groupMessageAvatar(
                    userID: message.senderID,
                    profile: profile
                )
            } else {
                Spacer(minLength: 44)
            }

            VStack(
                alignment:
                    mine ? .trailing : .leading,
                spacing: 4
            ) {
                Text(
                    mine
                        ? "You"
                        : (
                            profile?.usernameLabel
                                .isEmpty == false
                                ? profile!.usernameLabel
                                : message.senderName
                        )
                )
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

                Text(message.body)
                    .font(.subheadline)
                    .foregroundStyle(
                        mine
                            ? Color.white
                            : ATHLTHTheme.primaryText
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background {
                        if mine {
                            RoundedRectangle(
                                cornerRadius: 15,
                                style: .continuous
                            )
                            .fill(
                                LinearGradient(
                                    colors: [
                                        clubForest,
                                        clubEmerald
                                    ],
                                    startPoint:
                                        .topLeading,
                                    endPoint:
                                        .bottomTrailing
                                )
                            )
                        } else {
                            RoundedRectangle(
                                cornerRadius: 15,
                                style: .continuous
                            )
                            .fill(
                                ATHLTHTheme.card
                            )
                        }
                    }
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: 15,
                            style: .continuous
                        )
                        .stroke(
                            mine
                                ? clubEmerald
                                    .opacity(0.22)
                                : ATHLTHTheme
                                    .border
                                    .opacity(0.60),
                            lineWidth: 0.7
                        )
                    }

                Text(
                    message.createdAt.formatted(
                        date: .omitted,
                        time: .shortened
                    )
                )
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            }

            if mine {
                groupMessageAvatar(
                    userID: message.senderID,
                    profile: profile
                )
            } else {
                Spacer(minLength: 44)
            }
        }
    }

    @ViewBuilder
    private func groupMessageAvatar(
        userID: UUID,
        profile: SocialProfileCard?
    ) -> some View {
        NavigationLink {
            FriendProfileView(userID: userID)
        } label: {
            if let profile {
                CommunityGroupProfileAvatar(
                    profile: profile,
                    size: 32
                )
            } else {
                Image(
                    systemName:
                        "person.crop.circle.fill"
                )
                .font(.system(size: 31))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Open sender profile"
        )
    }

    private func groupChallengeCard(
        _ challenge: CommunityGroupChallengeRecord
    ) -> some View {
        let progress = groups.challengeProgress(challenge)
        let fraction = min(max(progress / challenge.targetValue, 0), 1)

        return VStack(alignment: .leading, spacing: 9) {
            if let imageURL = challenge.imageURL,
               !imageURL.isEmpty {
                communityContentCover(
                    imageURL,
                    height: 140
                )
            }

            HStack {
                Label(
                    challenge.title,
                    systemImage: challenge.metric.icon
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

                Spacer()

                Text(
                    String(
                        format: "%.0f%%",
                        fraction * 100
                    )
                )
                .font(.caption.weight(.bold))
                .foregroundStyle(clubForest)
            }

            if let configuration =
                challenge.activityConfiguration {
                Text(configuration.compactSummary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        clubForest
                    )
            }

            ProgressView(value: fraction)
                .tint(clubEmerald)

            HStack {
                Text(
                    progressText(
                        progress,
                        metric: challenge.metric
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                Text(
                    "Goal " +
                    targetText(
                        challenge.targetValue,
                        metric: challenge.metric
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            ATHLTHTheme.cardWarm.opacity(0.70),
            in: RoundedRectangle(cornerRadius: 15)
        )
    }

    @ViewBuilder
    private func communityContentCover(
        _ value: String,
        height: CGFloat
    ) -> some View {
        ATHLTHArtworkImage(
            reference: value,
            fallbackAssetName:
                "CommunityHero"
        )
        .athlthBoundedFill()
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
        )
    }

    private func eventDetailText(
        _ event: CommunityGroupEventRecord
    ) -> String {
        var parts = [
            event.startsAt.formatted(
                date: .abbreviated,
                time: .shortened
            )
        ]

        let meeting = event.meetingName
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        if !meeting.isEmpty {
            parts.append(meeting)
        }

        return parts.joined(separator: " · ")
    }

    private func groupContentStatusColor(
        _ status: CommunityGroupContentStatus
    ) -> Color {
        switch status {
        case .draft:
            return .secondary
        case .upcoming:
            return .blue
        case .live:
            return .green
        case .completed:
            return clubEmerald
        case .cancelled:
            return .red
        }
    }

    private func eventIcon(_ activity: String) -> String {
        switch activity {
        case "running": return "figure.run"
        case "walking": return "figure.walk"
        case "strength": return "dumbbell.fill"
        case "cycling": return "figure.outdoor.cycle"
        case "hike": return "figure.hiking"
        default: return "person.3.fill"
        }
    }

    private func progressText(
        _ value: Double,
        metric: CommunityGroupChallengeMetric
    ) -> String {
        switch metric {
        case .distanceKM:
            return String(format: "%.1f km", value)
        case .workouts:
            return "\(Int(value.rounded())) workouts"
        case .activeMinutes:
            return "\(Int(value.rounded())) min"
        case .fastestTime:
            let seconds = max(Int(value.rounded()), 0)
            return String(
                format: "%d:%02d",
                seconds / 60,
                seconds % 60
            )
        case .strengthVolume:
            return String(format: "%.0f kg", value)
        case .heaviestWeight:
            return String(format: "%.1f kg", value)
        case .strengthReps:
            return "\(Int(value.rounded())) reps"
        }
    }

    private func targetText(
        _ value: Double,
        metric: CommunityGroupChallengeMetric
    ) -> String {
        switch metric {
        case .distanceKM:
            return String(format: "%.0f km", value)
        case .workouts:
            return "\(Int(value.rounded())) workouts"
        case .activeMinutes:
            return "\(Int(value.rounded())) min"
        case .fastestTime:
            return "Fastest time"
        case .strengthVolume:
            return String(format: "%.0f kg", value)
        case .heaviestWeight:
            return String(format: "%.1f kg", value)
        case .strengthReps:
            return "\(Int(value.rounded())) reps"
        }
    }
}

struct CommunityGroupCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var groups: CommunityGroupStore

    @State private var name = ""
    @State private var summary = ""
    @State private var locationName = ""
    @State private var visibility = "public"
    @State private var joinMode = "open"
    @State private var membersCanCreateContent = true
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var cropRequest:
        CommunityImageCropRequest?
    @State private var headerCropRequest:
        CommunityImageCropRequest?
    @State private var selectedHeaderPhoto: PhotosPickerItem?
    @State private var selectedHeaderImageData: Data?
    @State private var selectedHeaderArtwork:
        ATHLTHStandardArtwork?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    createClubPreview
                        .listRowInsets(
                            EdgeInsets(
                                top: 8,
                                leading: 16,
                                bottom: 4,
                                trailing: 16
                            )
                        )
                        .listRowBackground(
                            Color.clear
                        )
                }

                Section {
                    VStack(
                        alignment: .leading,
                        spacing: 12
                    ) {
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Choose a ready-made ATHLTH image for the Club header.",
                                norwegian:
                                    "Velg et ferdig ATHLTH-bilde til klubbens header."
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )

                        ATHLTHStandardArtworkPicker(
                            selection: Binding(
                                get: {
                                    selectedHeaderArtwork
                                },
                                set: { artwork in
                                    selectedHeaderArtwork =
                                        artwork

                                    if artwork != nil {
                                        selectedHeaderPhoto =
                                            nil
                                        selectedHeaderImageData =
                                            nil
                                    }
                                }
                            )
                        )

                        if selectedHeaderArtwork != nil ||
                            selectedHeaderImageData != nil {
                            Button {
                                selectedHeaderArtwork =
                                    nil
                                selectedHeaderImageData =
                                    nil
                                selectedHeaderPhoto =
                                    nil
                            } label: {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Reset header",
                                        norwegian:
                                            "Tilbakestill header"
                                    ),
                                    systemImage:
                                        "arrow.counterclockwise"
                                )
                                .font(
                                    .caption.weight(
                                        .semibold
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(
                                ATHLTHTheme
                                    .accentDeep
                            )
                        }
                    }
                    .padding(
                        .vertical,
                        4
                    )
                } header: {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "ATHLTH images",
                            norwegian:
                                "ATHLTH-bilder"
                        )
                    )
                }

                Section(
                    ATHLTHLocalization.choose(
                        english: "Club info",
                        norwegian: "Klubbinfo"
                    )
                ) {
                    TextField(
                        ATHLTHLocalization.choose(
                            english:
                                "Club name",
                            norwegian:
                                "Klubbnavn"
                        ),
                        text: $name
                    )

                    TextField(
                        ATHLTHLocalization.choose(
                            english:
                                "Location (optional)",
                            norwegian:
                                "Sted (valgfritt)"
                        ),
                        text:
                            $locationName
                    )
                    .textContentType(
                        .location
                    )

                    TextField(
                        ATHLTHLocalization.choose(
                            english:
                                "Description",
                            norwegian:
                                "Beskrivelse"
                        ),
                        text: $summary,
                        axis: .vertical
                    )
                    .lineLimit(2...5)
                }

                Section(
                    ATHLTHLocalization.choose(
                        english: "Visibility",
                        norwegian: "Synlighet"
                    )
                ) {
                    Picker(
                        ATHLTHLocalization.choose(
                            english:
                                "Club visibility",
                            norwegian:
                                "Hvem kan se klubben"
                        ),
                        selection:
                            $visibility
                    ) {
                        Label(
                            ATHLTHLocalization.choose(
                                english:
                                    "Public",
                                norwegian:
                                    "Offentlig"
                            ),
                            systemImage:
                                "globe"
                        )
                        .tag("public")

                        Label(
                            ATHLTHLocalization.choose(
                                english:
                                    "Private",
                                norwegian:
                                    "Privat"
                            ),
                            systemImage:
                                "lock.fill"
                        )
                        .tag("private")
                    }
                    .pickerStyle(
                        .segmented
                    )

                    Text(
                        visibility == "public"
                            ? ATHLTHLocalization.choose(
                                english:
                                    "Public Clubs appear in Discover.",
                                norwegian:
                                    "Offentlige klubber vises i Utforsk."
                            )
                            : ATHLTHLocalization.choose(
                                english:
                                    "Private Clubs stay hidden from Discover.",
                                norwegian:
                                    "Private klubber skjules fra Utforsk."
                            )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )
                }

                Section(
                    ATHLTHLocalization.choose(
                        english: "Membership",
                        norwegian: "Medlemskap"
                    )
                ) {
                    Picker(
                        ATHLTHLocalization.choose(
                            english:
                                "Who can join",
                            norwegian:
                                "Hvem kan bli med"
                        ),
                        selection:
                            $joinMode
                    ) {
                        if visibility ==
                            "public" {
                            Text(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Open",
                                    norwegian:
                                        "Åpen"
                                )
                            )
                            .tag("open")
                        }

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Approval required",
                                norwegian:
                                    "Krever godkjenning"
                            )
                        )
                        .tag("approval")

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Invite only",
                                norwegian:
                                    "Kun invitasjon"
                            )
                        )
                        .tag(
                            "invite_only"
                        )
                    }

                    Text(
                        joinModeDescription
                    )
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )
                }

                Section(
                    ATHLTHLocalization.choose(
                        english:
                            "Member permissions",
                        norwegian:
                            "Medlemstillatelser"
                    )
                ) {
                    Toggle(
                        ATHLTHLocalization.choose(
                            english:
                                "Members can create events & challenges",
                            norwegian:
                                "Medlemmer kan opprette events og challenges"
                        ),
                        isOn:
                            $membersCanCreateContent
                    )

                    Text(
                        membersCanCreateContent
                            ? ATHLTHLocalization.choose(
                                english:
                                    "Members can create events and challenges.",
                                norwegian:
                                    "Medlemmer kan opprette events og challenges."
                            )
                            : ATHLTHLocalization.choose(
                                english:
                                    "Only Owner, Admin and Contributor can create them.",
                                norwegian:
                                    "Kun Owner, Admin og Contributor kan opprette dem."
                            )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )
                }

                Section {
                    Label(
                        ATHLTHLocalization.choose(
                            english:
                                "Owner has full control. Admin manages the Club, while Contributor can publish Club content.",
                            norwegian:
                                "Owner har full kontroll. Admin administrerer klubben, mens Contributor kan publisere klubbinnhold."
                        ),
                        systemImage:
                            "person.3.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )
                }
            }
            .scrollContentBackground(
                .hidden
            )
            .background(
                ATHLTHPremiumCanvas(
                    accent:
                        Color(
                            red: 0.055,
                            green: 0.49,
                            blue: 0.32
                        )
                        .opacity(0.13)
                )
                .ignoresSafeArea()
            )
            .tint(
                Color(
                    red: 0.025,
                    green: 0.30,
                    blue: 0.21
                )
            )
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english:
                        "Create Club",
                    norwegian:
                        "Opprett klubb"
                )
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
            .toolbar {
                ToolbarItem(
                    placement:
                        .cancellationAction
                ) {
                    Button(
                        ATHLTHLocalization.choose(
                            english:
                                "Cancel",
                            norwegian:
                                "Avbryt"
                        )
                    ) {
                        dismiss()
                    }
                }

                ToolbarItem(
                    placement:
                        .confirmationAction
                ) {
                    Button(
                        saving
                            ? ATHLTHLocalization.choose(
                                english:
                                    "Creating…",
                                norwegian:
                                    "Oppretter…"
                            )
                            : ATHLTHLocalization.choose(
                                english:
                                    "Create",
                                norwegian:
                                    "Opprett"
                            )
                    ) {
                        Task {
                            saving = true
                            let ok =
                                await groups
                                    .createGroup(
                                        name:
                                            name,
                                        summary:
                                            summary,
                                        locationName:
                                            locationName,
                                        visibility:
                                            visibility,
                                        joinMode:
                                            joinMode,
                                        membersCanCreateContent:
                                            membersCanCreateContent,
                                        imageJPEGData:
                                            selectedImageData,
                                        headerImageJPEGData:
                                            selectedHeaderImageData,
                                        headerArtworkReference:
                                            selectedHeaderArtwork?
                                                .reference
                                    )
                            saving = false

                            if ok {
                                dismiss()
                            }
                        }
                    }
                    .disabled(
                        name
                            .trimmingCharacters(
                                in:
                                    .whitespacesAndNewlines
                            )
                            .count < 2 ||
                        saving
                    )
                }
            }
            .onChange(
                of: visibility
            ) { _, value in
                if value == "private" &&
                    joinMode == "open" {
                    joinMode =
                        "invite_only"
                }
            }
            .onChange(
                of: selectedPhoto
            ) { _, item in
                guard let item else {
                    return
                }

                Task {
                    do {
                        guard let data =
                                try await item
                                    .loadTransferable(
                                        type:
                                            Data.self
                                    )
                        else {
                            groups.errorMessage =
                                "ATHLTH could not prepare that image. Try another photo."
                            selectedPhoto =
                                nil
                            return
                        }

                        guard let prepared =
                                await CommunityImageProcessor
                                    .prepareJPEG(
                                        data,
                                        maxPixelSize:
                                            2_400,
                                        quality:
                                            0.92
                                    ),
                              let image =
                                UIImage(
                                    data:
                                        prepared
                                )
                        else {
                            groups.errorMessage =
                                "ATHLTH could not prepare that image. Try another photo."
                            selectedPhoto =
                                nil
                            return
                        }

                        selectedPhoto =
                            nil
                        cropRequest =
                            CommunityImageCropRequest(
                                image: image,
                                target:
                                    .clubImage
                            )
                    } catch {
                        selectedPhoto =
                            nil
                        groups.errorMessage =
                            error
                                .localizedDescription
                    }
                }
            }
            .onChange(
                of: selectedHeaderPhoto
            ) { _, item in
                guard let item else {
                    return
                }

                Task {
                    do {
                        guard let data =
                                try await item
                                    .loadTransferable(
                                        type:
                                            Data.self
                                    )
                        else {
                            groups.errorMessage =
                                "ATHLTH could not prepare that header image. Try another photo."
                            selectedHeaderPhoto =
                                nil
                            return
                        }

                        guard let prepared =
                                await CommunityImageProcessor
                                    .prepareJPEG(
                                        data,
                                        maxPixelSize:
                                            2_400,
                                        quality:
                                            0.92
                                    ),
                              let image =
                                UIImage(
                                    data:
                                        prepared
                                )
                        else {
                            groups.errorMessage =
                                "ATHLTH could not prepare that header image. Try another photo."
                            selectedHeaderPhoto =
                                nil
                            return
                        }

                        selectedHeaderPhoto =
                            nil
                        headerCropRequest =
                            CommunityImageCropRequest(
                                image: image,
                                target:
                                    .wideCover
                            )
                    } catch {
                        selectedHeaderPhoto =
                            nil
                        groups.errorMessage =
                            error
                                .localizedDescription
                    }
                }
            }
            .fullScreenCover(
                item:
                    $cropRequest
            ) { request in
                CommunityImageCropEditor(
                    request: request
                ) { croppedData in
                    selectedImageData =
                        croppedData
                }
            }
            .fullScreenCover(
                item:
                    $headerCropRequest
            ) { request in
                CommunityImageCropEditor(
                    request: request
                ) { croppedData in
                    selectedHeaderImageData =
                        croppedData
                    selectedHeaderArtwork =
                        nil
                }
            }
        }
    }

    @ViewBuilder
    private var createClubPreview: some View {
        GeometryReader { proxy in
            ZStack(
                alignment: .bottomLeading
            ) {
                createHeaderPreviewBackground
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height
                    )
                    .clipped()

                LinearGradient(
                    colors: [
                        Color.black.opacity(
                            0.05
                        ),
                        Color.black.opacity(
                            0.18
                        ),
                        Color.black.opacity(
                            0.74
                        )
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                LinearGradient(
                    colors: [
                        Color.black.opacity(
                            0.38
                        ),
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        PhotosPicker(
                            selection:
                                $selectedHeaderPhoto,
                            matching:
                                .images
                        ) {
                            createPreviewMediaButton(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Change header",
                                    norwegian:
                                        "Endre header"
                                ),
                                icon: "photo"
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(
                            maxWidth:
                                .infinity
                        )

                        PhotosPicker(
                            selection:
                                $selectedPhoto,
                            matching:
                                .images
                        ) {
                            createPreviewMediaButton(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Club photo",
                                    norwegian:
                                        "Profilbilde"
                                ),
                                icon:
                                    "person.crop.square"
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(
                            maxWidth:
                                .infinity
                        )
                    }
                    .frame(
                        maxWidth:
                            .infinity
                    )
                    .padding(
                        .horizontal,
                        12
                    )
                    .padding(
                        .top,
                        12
                    )

                    Spacer()
                }
                .frame(
                    width:
                        proxy.size.width,
                    height:
                        proxy.size.height
                )

                HStack(
                    alignment: .bottom,
                    spacing: 10
                ) {
                    ZStack(
                        alignment:
                            .bottomTrailing
                    ) {
                        createProfileImagePreview
                            .frame(
                                width: 62,
                                height: 62
                            )

                        PhotosPicker(
                            selection:
                                $selectedPhoto,
                            matching:
                                .images
                        ) {
                            Image(
                                systemName:
                                    "pencil"
                            )
                            .font(
                                .system(
                                    size: 10,
                                    weight:
                                        .bold
                                )
                            )
                            .foregroundStyle(
                                .white
                            )
                            .frame(
                                width: 24,
                                height: 24
                            )
                            .background(
                                Color(
                                    red: 0.025,
                                    green: 0.30,
                                    blue: 0.21
                                ),
                                in: Circle()
                            )
                            .overlay {
                                Circle()
                                    .stroke(
                                        Color.white,
                                        lineWidth:
                                            2
                                    )
                            }
                        }
                        .buttonStyle(
                            .plain
                        )
                        .offset(
                            x: 3,
                            y: 3
                        )
                    }
                    .frame(
                        width: 62,
                        height: 62
                    )
                    .layoutPriority(1)

                    VStack(
                        alignment: .leading,
                        spacing: 4
                    ) {
                        Text(
                            name
                                .trimmingCharacters(
                                    in:
                                        .whitespacesAndNewlines
                                )
                                .isEmpty
                                ? ATHLTHLocalization.choose(
                                    english:
                                        "Your Club",
                                    norwegian:
                                        "Din klubb"
                                )
                                : name
                        )
                        .font(
                            .system(
                                size: 22,
                                weight: .bold,
                                design:
                                    .rounded
                            )
                        )
                        .foregroundStyle(
                            .white
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(
                            0.72
                        )
                        .frame(
                            maxWidth:
                                .infinity,
                            alignment:
                                .leading
                        )

                        let cleanSummary =
                            summary
                                .trimmingCharacters(
                                    in:
                                        .whitespacesAndNewlines
                                )

                        if !cleanSummary.isEmpty {
                            Text(
                                cleanSummary
                            )
                            .font(
                                .system(
                                    size: 10
                                )
                            )
                            .foregroundStyle(
                                .white
                                    .opacity(
                                        0.90
                                    )
                            )
                            .lineLimit(1)
                            .frame(
                                maxWidth:
                                    .infinity,
                                alignment:
                                    .leading
                            )
                        }

                        HStack(
                            spacing: 5
                        ) {
                            createPreviewChip(
                                visibility ==
                                    "private"
                                    ? ATHLTHLocalization.choose(
                                        english:
                                            "Private",
                                        norwegian:
                                            "Privat"
                                    )
                                    : ATHLTHLocalization.choose(
                                        english:
                                            "Public",
                                        norwegian:
                                            "Offentlig"
                                    ),
                                icon:
                                    visibility ==
                                        "private"
                                        ? "lock.fill"
                                        : "globe"
                            )

                            createPreviewChip(
                                createMembershipPreviewTitle,
                                icon:
                                    joinMode ==
                                        "open"
                                        ? "person.badge.plus"
                                        : "person.badge.clock"
                            )

                            Spacer(
                                minLength: 0
                            )
                        }
                        .frame(
                            maxWidth:
                                .infinity,
                            alignment:
                                .leading
                        )

                        let cleanLocation =
                            locationName
                                .trimmingCharacters(
                                    in:
                                        .whitespacesAndNewlines
                                )

                        if !cleanLocation.isEmpty {
                            Label(
                                cleanLocation,
                                systemImage:
                                    "location.fill"
                            )
                            .font(
                                .system(
                                    size: 9,
                                    weight:
                                        .medium
                                )
                            )
                            .foregroundStyle(
                                .white.opacity(
                                    0.86
                                )
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(
                                0.78
                            )
                        }
                    }
                    .frame(
                        maxWidth:
                            .infinity,
                        alignment:
                            .leading
                    )
                }
                .padding(
                    .horizontal,
                    14
                )
                .padding(
                    .bottom,
                    14
                )
                .frame(
                    width:
                        proxy.size.width,
                    alignment:
                        .leading
                )
            }
            .frame(
                width:
                    proxy.size.width,
                height:
                    proxy.size.height
            )
            .clipped()
        }
        .frame(height: 242)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 24,
                style:
                    .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 24,
                style:
                    .continuous
            )
            .stroke(
                Color.white
                    .opacity(
                        0.40
                    ),
                lineWidth: 1
            )
        }
        .shadow(
            color:
                Color.black
                    .opacity(0.10),
            radius: 16,
            y: 7
        )
    }

    nonisolated private func createPreviewMediaButton(
        _ title: String,
        icon: String
    ) -> some View {
        HStack(
            spacing: 6
        ) {
            Image(
                systemName: icon
            )
            .font(
                .system(
                    size: 12,
                    weight:
                        .semibold
                )
            )

            Text(title)
                .font(
                    .system(
                        size: 11,
                        weight:
                            .semibold
                    )
                )
                .lineLimit(1)
                .minimumScaleFactor(
                    0.78
                )
        }
        .foregroundStyle(
            .white
        )
        .frame(
            maxWidth:
                .infinity
        )
        .frame(height: 34)
        .padding(
            .horizontal,
            8
        )
        .background(
            Color.black
                .opacity(
                    0.36
                ),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(
                    Color.white
                        .opacity(
                            0.30
                        ),
                    lineWidth:
                        0.8
                )
        }
    }

    @ViewBuilder
    private var createHeaderPreviewBackground:
        some View {
        if let selectedHeaderImageData,
           let image =
                UIImage(
                    data:
                        selectedHeaderImageData
                ) {
            Image(
                uiImage: image
            )
            .resizable()
            .scaledToFill()
            .athlthBoundedFill()
        } else if let selectedHeaderArtwork,
                  let image =
                    selectedHeaderArtwork
                        .resolvedUIImage {
            Image(
                uiImage: image
            )
            .resizable()
            .scaledToFill()
            .athlthBoundedFill()
            .scaleEffect(
                1.08,
                anchor:
                    .center
            )
        } else {
            Image(
                "CommunityHero"
            )
            .resizable()
            .interpolation(
                .medium
            )
            .scaledToFill()
        }
    }

    @ViewBuilder
    private var createProfileImagePreview:
        some View {
        Group {
            if let selectedImageData,
               let image =
                    UIImage(
                        data:
                            selectedImageData
                    ) {
                Image(
                    uiImage: image
                )
                .resizable()
                .scaledToFill()
            } else {
                LinearGradient(
                    colors: [
                        Color(
                            red: 0.025,
                            green: 0.30,
                            blue: 0.21
                        ),
                        Color(
                            red: 0.055,
                            green: 0.49,
                            blue: 0.32
                        )
                    ],
                    startPoint:
                        .topLeading,
                    endPoint:
                        .bottomTrailing
                )
                .overlay {
                    Image(
                        systemName:
                            "person.3.fill"
                    )
                    .font(
                        .system(
                            size: 28,
                            weight:
                                .semibold
                        )
                    )
                    .foregroundStyle(
                        .white
                    )
                }
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18,
                style:
                    .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style:
                    .continuous
            )
            .stroke(
                Color.white,
                lineWidth: 2
            )
        }
        .shadow(
            color:
                Color.black
                    .opacity(0.22),
            radius: 8,
            y: 4
        )
    }

    private func createPreviewChip(
        _ title: String,
        icon: String
    ) -> some View {
        Label(
            title,
            systemImage: icon
        )
        .font(
            .system(
                size: 9,
                weight:
                    .semibold
            )
        )
        .foregroundStyle(
            .white.opacity(
                0.94
            )
        )
        .lineLimit(1)
        .minimumScaleFactor(
            0.70
        )
        .padding(
            .horizontal,
            7
        )
        .frame(height: 24)
        .background(
            Color.black
                .opacity(0.28),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(
                    Color.white
                        .opacity(
                            0.22
                        ),
                    lineWidth:
                        0.6
                )
        }
    }

    private var createMembershipPreviewTitle:
        String {
        switch joinMode {
        case "open":
            return ATHLTHLocalization.choose(
                english: "Open",
                norwegian: "Åpen"
            )
        case "approval":
            return ATHLTHLocalization.choose(
                english:
                    "Approval",
                norwegian:
                    "Godkjenning"
            )
        default:
            return ATHLTHLocalization.choose(
                english:
                    "Invite only",
                norwegian:
                    "Kun invitasjon"
            )
        }
    }

    private var joinModeDescription: String {
        switch joinMode {
        case "open":
            return "Anyone can join immediately."
        case "approval":
            return "People request access. Owner or Admin approves them."
        default:
            return "Only people invited by Owner or Admin can join."
        }
    }

}

struct CommunityGroupSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var groups: CommunityGroupStore

    let group: CommunityGroupRecord

    @State private var name: String
    @State private var summary: String
    @State private var locationName: String
    @State private var visibility: String
    @State private var joinMode: String
    @State private var membersCanCreateContent: Bool
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var cropRequest:
        CommunityImageCropRequest?
    @State private var saveError: String?
    @State private var selectedHeaderPhoto: PhotosPickerItem?
    @State private var selectedHeaderImageData: Data?
    @State private var selectedHeaderArtwork:
        ATHLTHStandardArtwork?
    @State private var selectedFeaturedChallengeID: UUID?
    @State private var saving = false
    @State private var deleting = false
    @State private var showingDeleteConfirmation = false

    init(group: CommunityGroupRecord) {
        self.group = group
        _name = State(initialValue: group.name)
        _summary = State(initialValue: group.summary)
        _locationName = State(
            initialValue: group.locationName
        )
        _visibility = State(initialValue: group.visibility)
        _joinMode = State(initialValue: group.joinMode)
        _membersCanCreateContent = State(
            initialValue: group.membersCanCreateContent
        )
        _selectedHeaderArtwork = State(
            initialValue:
                ATHLTHStandardArtwork(
                    reference:
                        group.headerImageURL
                )
        )
        _selectedFeaturedChallengeID = State(
            initialValue: group.featuredChallengeID
        )
    }

    private var currentGroup: CommunityGroupRecord {
        groups.group(for: group.id) ?? group
    }

    private var clubForest: Color {
        Color(
            red: 0.025,
            green: 0.30,
            blue: 0.21
        )
    }

    private var clubEmerald: Color {
        Color(
            red: 0.055,
            green: 0.49,
            blue: 0.32
        )
    }

    private var clubMint: Color {
        Color(
            red: 0.90,
            green: 0.96,
            blue: 0.92
        )
    }

    private var clubSage: Color {
        Color(
            red: 0.77,
            green: 0.88,
            blue: 0.81
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ATHLTHPremiumCanvas(
                    accent:
                        clubEmerald.opacity(
                            0.14
                        )
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(
                        alignment: .leading,
                        spacing: 14
                    ) {
                        compactMediaCard
                        clubIdentityCard
                        clubSetupCard
                        permissionsCard

                        if groups.isOwner(
                            of: currentGroup
                        ) {
                            dangerCard
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 28)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english:
                        "Club Settings",
                    norwegian:
                        "Klubbinnstillinger"
                )
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
            .toolbar {
                ToolbarItem(
                    placement:
                        .cancellationAction
                ) {
                    Button(
                        ATHLTHLocalization.choose(
                            english:
                                "Cancel",
                            norwegian:
                                "Avbryt"
                        )
                    ) {
                        dismiss()
                    }
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                }

                ToolbarItem(
                    placement:
                        .confirmationAction
                ) {
                    Button {
                        Task {
                            await saveChanges()
                        }
                    } label: {
                        Text(
                            saving
                                ? ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Saving…",
                                        norwegian:
                                            "Lagrer…"
                                    )
                                : ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Save",
                                        norwegian:
                                            "Lagre"
                                    )
                        )
                        .font(
                            .subheadline
                                .weight(
                                    .semibold
                                )
                        )
                        .foregroundStyle(
                            .white
                        )
                        .padding(
                            .horizontal,
                            17
                        )
                        .frame(height: 38)
                        .background(
                            LinearGradient(
                                colors: [
                                    clubForest,
                                    clubEmerald
                                ],
                                startPoint:
                                    .leading,
                                endPoint:
                                    .trailing
                            ),
                            in: Capsule()
                        )
                        .opacity(
                            canSave
                                ? 1
                                : 0.35
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)
                }
            }
            .onChange(
                of: visibility
            ) { _, value in
                if value == "private" &&
                    joinMode == "open" {
                    joinMode =
                        "invite_only"
                }
            }
            .onChange(
                of: selectedPhoto
            ) { _, item in
                guard let item else {
                    return
                }

                Task {
                    do {
                        guard let data =
                                try await item
                                    .loadTransferable(
                                        type:
                                            Data.self
                                    )
                        else {
                            saveError =
                                ATHLTHLocalization.choose(
                                    english:
                                        "ATHLTH could not prepare that Club image. Try another photo.",
                                    norwegian:
                                        "ATHLTH klarte ikke å klargjøre Club-bildet. Prøv et annet bilde."
                                )
                            selectedPhoto = nil
                            return
                        }

                        guard let prepared =
                                await CommunityImageProcessor
                                    .prepareJPEG(
                                        data,
                                        maxPixelSize:
                                            2_400,
                                        quality: 0.92
                                    ),
                              let image =
                                UIImage(
                                    data:
                                        prepared
                                )
                        else {
                            saveError =
                                ATHLTHLocalization.choose(
                                    english:
                                        "ATHLTH could not prepare that Club image. Try another photo.",
                                    norwegian:
                                        "ATHLTH klarte ikke å klargjøre Club-bildet. Prøv et annet bilde."
                                )
                            selectedPhoto = nil
                            return
                        }

                        selectedPhoto = nil
                        cropRequest =
                            CommunityImageCropRequest(
                                image: image,
                                target:
                                    .clubImage
                            )
                    } catch {
                        selectedPhoto = nil
                        saveError =
                            error.localizedDescription
                    }
                }
            }
            .onChange(
                of: selectedHeaderPhoto
            ) { _, item in
                guard let item else {
                    return
                }

                Task {
                    do {
                        guard let data =
                                try await item
                                    .loadTransferable(
                                        type:
                                            Data.self
                                    )
                        else {
                            saveError =
                                ATHLTHLocalization.choose(
                                    english:
                                        "ATHLTH could not prepare that header image. Try another photo.",
                                    norwegian:
                                        "ATHLTH klarte ikke å klargjøre headerbildet. Prøv et annet bilde."
                                )
                            selectedHeaderPhoto =
                                nil
                            return
                        }

                        guard let prepared =
                                await CommunityImageProcessor
                                    .prepareJPEG(
                                        data,
                                        maxPixelSize:
                                            2_400,
                                        quality: 0.92
                                    ),
                              let image =
                                UIImage(
                                    data:
                                        prepared
                                )
                        else {
                            saveError =
                                ATHLTHLocalization.choose(
                                    english:
                                        "ATHLTH could not prepare that header image. Try another photo.",
                                    norwegian:
                                        "ATHLTH klarte ikke å klargjøre headerbildet. Prøv et annet bilde."
                                )
                            selectedHeaderPhoto =
                                nil
                            return
                        }

                        selectedHeaderPhoto = nil
                        cropRequest =
                            CommunityImageCropRequest(
                                image: image,
                                target:
                                    .wideCover
                            )
                    } catch {
                        selectedHeaderPhoto = nil
                        saveError =
                            error.localizedDescription
                    }
                }
            }
            .fullScreenCover(
                item: $cropRequest
            ) { request in
                CommunityImageCropEditor(
                    request: request
                ) { croppedData in
                    switch request.target {
                    case .clubImage:
                        selectedImageData =
                            croppedData
                    case .wideCover:
                        selectedHeaderImageData =
                            croppedData
                        selectedHeaderArtwork =
                            nil
                    }
                }
            }
            .alert(
                ATHLTHLocalization.choose(
                    english:
                        "Could not save Club image",
                    norwegian:
                        "Kunne ikke lagre Club-bildet"
                ),
                isPresented: Binding(
                    get: {
                        saveError != nil
                    },
                    set: {
                        if !$0 {
                            saveError = nil
                        }
                    }
                )
            ) {
                Button(
                    "OK",
                    role: .cancel
                ) {}
            } message: {
                Text(saveError ?? "")
            }
            .confirmationDialog(
                ATHLTHLocalization.format(
                    english:
                        "Delete %@?",
                    norwegian:
                        "Slette %@?",
                    currentGroup.name
                ),
                isPresented:
                    $showingDeleteConfirmation,
                titleVisibility:
                    .visible
            ) {
                Button(
                    ATHLTHLocalization.choose(
                        english:
                            "Delete Club",
                        norwegian:
                            "Slett Club"
                    ),
                    role: .destructive
                ) {
                    Task {
                        deleting = true
                        let deleted =
                            await groups
                                .deleteGroup(
                                    currentGroup
                                )
                        deleting = false

                        if deleted {
                            dismiss()
                        }
                    }
                }

                Button(
                    ATHLTHLocalization.choose(
                        english:
                            "Cancel",
                        norwegian:
                            "Avbryt"
                    ),
                    role: .cancel
                ) {}
            } message: {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "This cannot be undone. All Club content will be permanently removed.",
                        norwegian:
                            "Dette kan ikke angres. Alt innhold i Club-en blir slettet permanent."
                    )
                )
            }
        }
    }

    private var canSave: Bool {
        name.trimmingCharacters(
            in:
                .whitespacesAndNewlines
        ).count >= 2 &&
        !saving &&
        !deleting
    }

    private var compactMediaCard:
        some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            sectionTitle(
                ATHLTHLocalization.choose(
                    english:
                        "Club identity",
                    norwegian:
                        "Club-identitet"
                ),
                systemImage:
                    "photo.on.rectangle.angled"
            )

            groupHeaderImagePreview
                .frame(height: 112)

            HStack(spacing: 8) {
                PhotosPicker(
                    selection:
                        $selectedHeaderPhoto,
                    matching: .images
                ) {
                    Label(
                        ATHLTHLocalization.choose(
                            english:
                                selectedHeaderImageData == nil
                                    ? "Upload your own image"
                                    : "Change uploaded image",
                            norwegian:
                                selectedHeaderImageData == nil
                                    ? "Last opp eget bilde"
                                    : "Bytt eget bilde"
                        ),
                        systemImage:
                            "square.and.arrow.up"
                    )
                    .font(
                        .subheadline
                            .weight(
                                .semibold
                            )
                    )
                    .foregroundStyle(
                        clubForest
                    )
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 42
                    )
                    .background(
                        clubMint,
                        in:
                            RoundedRectangle(
                                cornerRadius: 14,
                                style:
                                    .continuous
                            )
                    )
                }
                .buttonStyle(.plain)

                Menu {
                    if let selectedHeaderImageData,
                       let image =
                        UIImage(
                            data:
                                selectedHeaderImageData
                        ) {
                        Button {
                            cropRequest =
                                CommunityImageCropRequest(
                                    image: image,
                                    target:
                                        .wideCover
                                )
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Adjust header",
                                    norwegian:
                                        "Juster header"
                                ),
                                systemImage:
                                    "crop"
                            )
                        }
                    }

                    if selectedHeaderImageData != nil ||
                        (
                            selectedHeaderArtwork !=
                                nil &&
                            currentGroup
                                .headerImageURL !=
                                selectedHeaderArtwork?
                                    .reference
                        ) {
                        Button(
                            role: .destructive
                        ) {
                            selectedHeaderImageData =
                                nil
                            selectedHeaderPhoto = nil
                            selectedHeaderArtwork =
                                ATHLTHStandardArtwork(
                                    reference:
                                        currentGroup
                                            .headerImageURL
                                )
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Reset header changes",
                                    norwegian:
                                        "Tilbakestill header"
                                ),
                                systemImage:
                                    "arrow.counterclockwise"
                            )
                        }
                    } else if currentGroup
                        .headerImageURL != nil {
                        Button(
                            role: .destructive
                        ) {
                            Task {
                                saving = true
                                let removed =
                                    await groups
                                        .removeGroupHeaderImage(
                                            currentGroup
                                        )
                                if removed {
                                    selectedHeaderArtwork =
                                        nil
                                    selectedHeaderImageData =
                                        nil
                                } else {
                                    saveError =
                                        groups
                                            .errorMessage
                                }
                                saving = false
                            }
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Remove header",
                                    norwegian:
                                        "Fjern header"
                                ),
                                systemImage:
                                    "trash"
                            )
                        }
                    }
                } label: {
                    Image(
                        systemName:
                            "ellipsis"
                    )
                    .font(
                        .system(
                            size: 14,
                            weight:
                                .semibold
                        )
                    )
                    .foregroundStyle(
                        clubForest
                    )
                    .frame(
                        width: 42,
                        height: 42
                    )
                    .background(
                        clubMint,
                        in:
                            RoundedRectangle(
                                cornerRadius: 14,
                                style:
                                    .continuous
                            )
                    )
                }
                .disabled(saving)
            }

            Text(
                "ATHLTH images"
            )
            .font(
                .caption
                    .weight(
                        .semibold
                    )
            )
            .foregroundStyle(
                clubForest
            )
            .padding(.top, 2)

            ATHLTHStandardArtworkPicker(
                selection:
                    Binding(
                        get: {
                            selectedHeaderArtwork
                        },
                        set: {
                            artwork in

                            selectedHeaderArtwork =
                                artwork
                            if artwork != nil {
                                selectedHeaderPhoto =
                                    nil
                                selectedHeaderImageData =
                                    nil
                            }
                        }
                    )
            )
        }
        .padding(14)
        .background(
            Color.white
                .opacity(0.95),
            in:
                RoundedRectangle(
                    cornerRadius: 22,
                    style:
                        .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
            .stroke(
                clubSage.opacity(
                    0.46
                ),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                clubForest.opacity(
                    0.05
                ),
            radius: 12,
            y: 5
        )
    }

    private var clubIdentityCard:
        some View {
        VStack(
            alignment: .leading,
            spacing: 0
        ) {
            HStack(
                alignment: .center,
                spacing: 12
            ) {
                sectionTitle(
                    ATHLTHLocalization.choose(
                        english:
                            "Club details",
                        norwegian:
                            "Club-detaljer"
                    ),
                    systemImage:
                        "pencil.line"
                )

                Spacer()

                PhotosPicker(
                    selection:
                        $selectedPhoto,
                    matching: .images
                ) {
                    ZStack(
                        alignment:
                            .bottomTrailing
                    ) {
                        groupImagePreview
                            .frame(
                                width: 58,
                                height: 58
                            )
                            .clipShape(
                                Circle()
                            )
                            .overlay {
                                Circle()
                                    .stroke(
                                        Color.white,
                                        lineWidth: 2
                                    )
                            }
                            .shadow(
                                color:
                                    Color.black
                                        .opacity(
                                            0.10
                                        ),
                                radius: 7,
                                y: 3
                            )

                        Image(
                            systemName:
                                "camera.fill"
                        )
                        .font(
                            .system(
                                size: 10,
                                weight:
                                    .bold
                            )
                        )
                        .foregroundStyle(
                            .white
                        )
                        .frame(
                            width: 22,
                            height: 22
                        )
                        .background(
                            clubEmerald,
                            in: Circle()
                        )
                        .overlay {
                            Circle()
                                .stroke(
                                    Color.white,
                                    lineWidth: 2
                                )
                        }
                        .offset(
                            x: 2,
                            y: 2
                        )
                    }
                    .contentShape(
                        Circle()
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    ATHLTHLocalization.choose(
                        english:
                            "Change Club image",
                        norwegian:
                            "Endre Club-bilde"
                    )
                )
            }
            .padding(
                .bottom,
                8
            )

            compactTextFieldRow(
                title:
                    ATHLTHLocalization
                        .choose(
                            english:
                                "Name",
                            norwegian:
                                "Navn"
                        ),
                text: $name,
                icon:
                    "textformat"
            )

            Divider()
                .opacity(0.55)

            compactTextFieldRow(
                title:
                    ATHLTHLocalization
                        .choose(
                            english:
                                "Location",
                            norwegian:
                                "Sted"
                        ),
                text:
                    $locationName,
                icon:
                    "location.fill"
            )
            .textContentType(
                .location
            )

            Divider()
                .opacity(0.55)

            VStack(
                alignment: .leading,
                spacing: 6
            ) {
                Label(
                    ATHLTHLocalization.choose(
                        english:
                            "Bio",
                        norwegian:
                            "Bio"
                    ),
                    systemImage:
                        "quote.bubble.fill"
                )
                .font(
                    .caption
                        .weight(
                            .semibold
                        )
                )
                .foregroundStyle(
                    clubForest
                )

                TextField(
                    ATHLTHLocalization.choose(
                        english:
                            "Describe your Club",
                        norwegian:
                            "Beskriv Club-en"
                    ),
                    text: $summary,
                    axis: .vertical
                )
                .lineLimit(1...3)
                .font(.subheadline)
            }
            .padding(
                .vertical,
                11
            )
        }
        .padding(
            .horizontal,
            14
        )
        .padding(
            .vertical,
            10
        )
        .background(
            Color.white
                .opacity(0.95),
            in:
                RoundedRectangle(
                    cornerRadius: 22,
                    style:
                        .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
            .stroke(
                clubSage.opacity(
                    0.40
                ),
                lineWidth: 0.8
            )
        }
    }

    private var clubSetupCard:
        some View {
        VStack(
            alignment: .leading,
            spacing: 0
        ) {
            sectionTitle(
                ATHLTHLocalization.choose(
                    english:
                        "Club setup",
                    norwegian:
                        "Club-oppsett"
                ),
                systemImage:
                    "slider.horizontal.3"
            )
            .padding(
                .bottom,
                8
            )

            Picker(
                selection:
                    $selectedFeaturedChallengeID
            ) {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "None",
                        norwegian:
                            "Ingen"
                    )
                )
                .tag(nil as UUID?)

                ForEach(
                    availableFeaturedChallenges
                ) {
                    challenge in

                    Text(
                        challenge.title
                    )
                    .tag(
                        challenge.id
                            as UUID?
                    )
                }
            } label: {
                compactSettingLabel(
                    icon:
                        "trophy.fill",
                    title:
                        ATHLTHLocalization
                            .choose(
                                english:
                                    "Featured challenge",
                                norwegian:
                                    "Fremhevet challenge"
                            )
                )
            }
            .pickerStyle(.menu)
            .tint(
                ATHLTHTheme
                    .primaryText
            )
            .frame(
                minHeight: 52
            )

            Divider()
                .opacity(0.55)

            Picker(
                selection:
                    $joinMode
            ) {
                if visibility ==
                    "public" {
                    Text(
                        ATHLTHLocalization
                            .choose(
                                english:
                                    "Open",
                                norwegian:
                                    "Åpen"
                            )
                    )
                    .tag("open")
                }

                Text(
                    ATHLTHLocalization
                        .choose(
                            english:
                                "Approval required",
                            norwegian:
                                "Godkjenning"
                        )
                )
                .tag("approval")

                Text(
                    ATHLTHLocalization
                        .choose(
                            english:
                                "Invite only",
                            norwegian:
                                "Kun invitasjon"
                        )
                )
                .tag(
                    "invite_only"
                )
            } label: {
                compactSettingLabel(
                    icon:
                        "person.2.fill",
                    title:
                        ATHLTHLocalization
                            .choose(
                                english:
                                    "Membership",
                                norwegian:
                                    "Medlemskap"
                            )
                )
            }
            .pickerStyle(.menu)
            .tint(
                ATHLTHTheme
                    .primaryText
            )
            .frame(
                minHeight: 52
            )

            Divider()
                .opacity(0.55)

            VStack(
                alignment: .leading,
                spacing: 8
            ) {
                compactSettingLabel(
                    icon:
                        "globe",
                    title:
                        ATHLTHLocalization
                            .choose(
                                english:
                                    "Visibility",
                                norwegian:
                                    "Synlighet"
                            )
                )

                Picker(
                    "",
                    selection:
                        $visibility
                ) {
                    Text(
                        ATHLTHLocalization
                            .choose(
                                english:
                                    "Public",
                                norwegian:
                                    "Offentlig"
                            )
                    )
                    .tag("public")

                    Text(
                        ATHLTHLocalization
                            .choose(
                                english:
                                    "Private",
                                norwegian:
                                    "Privat"
                            )
                    )
                    .tag("private")
                }
                .pickerStyle(
                    .segmented
                )
                .labelsHidden()
            }
            .padding(
                .vertical,
                10
            )
        }
        .padding(
            .horizontal,
            14
        )
        .padding(
            .vertical,
            10
        )
        .background(
            Color.white
                .opacity(0.95),
            in:
                RoundedRectangle(
                    cornerRadius: 22,
                    style:
                        .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
            .stroke(
                clubSage.opacity(
                    0.40
                ),
                lineWidth: 0.8
            )
        }
    }

    private var permissionsCard:
        some View {
        VStack(
            alignment: .leading,
            spacing: 0
        ) {
            sectionTitle(
                ATHLTHLocalization.choose(
                    english:
                        "Permissions",
                    norwegian:
                        "Tillatelser"
                ),
                systemImage:
                    "person.badge.key.fill"
            )
            .padding(
                .bottom,
                6
            )

            Toggle(
                isOn:
                    $membersCanCreateContent
            ) {
                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Members can create content",
                            norwegian:
                                "Medlemmer kan opprette innhold"
                        )
                    )
                    .font(
                        .subheadline
                            .weight(
                                .semibold
                            )
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Events and challenges",
                            norwegian:
                                "Events og challenges"
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                }
            }
            .tint(
                clubEmerald
            )
            .padding(
                .vertical,
                8
            )
        }
        .padding(
            .horizontal,
            14
        )
        .padding(
            .vertical,
            10
        )
        .background(
            Color.white
                .opacity(0.95),
            in:
                RoundedRectangle(
                    cornerRadius: 22,
                    style:
                        .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
            .stroke(
                clubSage.opacity(
                    0.40
                ),
                lineWidth: 0.8
            )
        }
    }

    private var dangerCard:
        some View {
        Button(
            role: .destructive
        ) {
            showingDeleteConfirmation =
                true
        } label: {
            HStack(spacing: 10) {
                Image(
                    systemName:
                        "trash"
                )

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Delete Club",
                        norwegian:
                            "Slett Club"
                    )
                )
                .font(
                    .subheadline
                        .weight(
                            .semibold
                        )
                )

                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(
                Color.red
                    .opacity(0.06),
                in:
                    RoundedRectangle(
                        cornerRadius: 18,
                        style:
                            .continuous
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(
            saving || deleting
        )
    }

    private func sectionTitle(
        _ title: String,
        systemImage: String
    ) -> some View {
        HStack(spacing: 8) {
            Image(
                systemName:
                    systemImage
            )
            .font(
                .system(
                    size: 12,
                    weight:
                        .semibold
                )
            )
            .foregroundStyle(
                clubForest
            )
            .frame(
                width: 28,
                height: 28
            )
            .background(
                clubMint,
                in: Circle()
            )

            Text(title)
                .font(
                    .headline
                        .weight(.bold)
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .primaryText
                )
        }
    }

    nonisolated private func compactActionChip(
        title: String,
        icon: String
    ) -> some View {
        let forest =
            Color(
                red: 0.025,
                green: 0.30,
                blue: 0.21
            )
        let mint =
            Color(
                red: 0.90,
                green: 0.96,
                blue: 0.92
            )

        return Label(
            title,
            systemImage: icon
        )
        .font(
            .caption
                .weight(
                    .semibold
                )
        )
        .foregroundStyle(
            forest
        )
        .padding(
            .horizontal,
            10
        )
        .frame(height: 34)
        .background(
            mint,
            in: Capsule()
        )
    }

    private func compactTextFieldRow(
        title: String,
        text: Binding<String>,
        icon: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(
                systemName: icon
            )
            .font(
                .system(
                    size: 12,
                    weight:
                        .semibold
                )
            )
            .foregroundStyle(
                clubForest
            )
            .frame(width: 18)

            TextField(
                title,
                text: text
            )
            .font(.subheadline)
        }
        .frame(
            minHeight: 48
        )
    }

    private func compactSettingLabel(
        icon: String,
        title: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(
                systemName: icon
            )
            .font(
                .system(
                    size: 12,
                    weight:
                        .semibold
                )
            )
            .foregroundStyle(
                clubForest
            )
            .frame(width: 18)

            Text(title)
                .font(
                    .subheadline
                        .weight(
                            .semibold
                        )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .primaryText
                )
        }
    }

    private var availableFeaturedChallenges:
        [CommunityGroupChallengeRecord] {
        let now = Date()

        return groups.challenges(in: currentGroup.id)
            .filter {
                $0.status != "draft" &&
                $0.status != "cancelled" &&
                $0.endsAt >= now
            }
            .sorted { lhs, rhs in
                let lhsActive =
                    lhs.startsAt <= now &&
                    lhs.endsAt >= now
                let rhsActive =
                    rhs.startsAt <= now &&
                    rhs.endsAt >= now

                if lhsActive != rhsActive {
                    return lhsActive
                }

                return lhs.startsAt < rhs.startsAt
            }
    }

    private var joinModeDescription: String {
        switch joinMode {
        case "open":
            return "Anyone can join immediately."
        case "approval":
            return "New members request access. Owner or Admin can approve them."
        default:
            return "Only people invited by Owner or Admin can join."
        }
    }

    private func saveChanges() async {
        saving = true

        var saved = await groups.updateGroup(
            currentGroup,
            name: name,
            locationName: locationName,
            summary: summary,
            visibility: visibility,
            joinMode: joinMode,
            membersCanCreateContent:
                membersCanCreateContent
        )

        if saved,
           let selectedImageData {
            saved = await groups.uploadGroupImage(
                currentGroup,
                jpegData: selectedImageData
            )
        }

        if saved,
           let selectedHeaderImageData {
            saved = await groups.uploadGroupHeaderImage(
                currentGroup,
                jpegData: selectedHeaderImageData
            )
        } else if saved,
                  let selectedHeaderArtwork,
                  currentGroup.headerImageURL !=
                    selectedHeaderArtwork.reference {
            saved = await groups.setGroupHeaderArtwork(
                currentGroup,
                artwork:
                    selectedHeaderArtwork
            )
        }

        if saved,
           selectedFeaturedChallengeID !=
            currentGroup.featuredChallengeID {
            saved = await groups.setFeaturedChallenge(
                selectedFeaturedChallengeID,
                in: currentGroup
            )
        }

        saving = false

        if saved {
            dismiss()
        } else {
            saveError =
                groups.errorMessage ??
                ATHLTHLocalization.choose(
                    english:
                        "ATHLTH could not save the Club changes.",
                    norwegian:
                        "ATHLTH klarte ikke å lagre Club-endringene."
                )
        }
    }

    @ViewBuilder
    private var groupImagePreview: some View {
        Group {
            if let selectedImageData,
               let image = UIImage(data: selectedImageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let value = currentGroup.imageURL,
                      let url = URL(string: value) {
                ATHLTHStorageImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        groupImagePlaceholder
                    }
                }
            } else {
                groupImagePlaceholder
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
        .clipped()
        .overlay {
            ZStack {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.66),
                        ATHLTHTheme.cardWarm.opacity(0.34),
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
                .stroke(
                    ATHLTHTheme.border,
                    lineWidth: 1
                )
            }
        }
    }

    @ViewBuilder
    private var groupHeaderImagePreview: some View {
        Group {
            if let selectedHeaderImageData,
               let image =
                    UIImage(
                        data:
                            selectedHeaderImageData
                    ) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .athlthBoundedFill()
            } else if let selectedHeaderArtwork,
                      let image =
                        selectedHeaderArtwork
                            .resolvedUIImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .athlthBoundedFill()
            } else if currentGroup.headerImageURL != nil {
                ATHLTHArtworkImage(
                    reference:
                        currentGroup
                            .headerImageURL,
                    fallbackAssetName:
                        "CommunityHero"
                )
            } else {
                groupHeaderImagePlaceholder
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
        .clipped()
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(
                ATHLTHTheme.border,
                lineWidth: 1
            )
        }
    }

    private var groupHeaderImagePlaceholder: some View {
        LinearGradient(
            colors: [
                ATHLTHTheme.accentDeep,
                ATHLTHTheme.accent,
                ATHLTHTheme.vitality.opacity(0.78)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white.opacity(0.86))
        }
    }

    private var groupImagePlaceholder: some View {
        RoundedRectangle(
            cornerRadius: 22,
            style: .continuous
        )
        .fill(ATHLTHTheme.accentSoft)
        .overlay {
            Image(systemName: "person.3.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
        }
    }

}

private struct CommunityGroupProfileAvatar: View {
    let profile: SocialProfileCard
    let size: CGFloat

    var body: some View {
        Group {
            if let value = profile.avatarURL,
               let url = URL(string: value) {
                ATHLTHStorageImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(
                    Color.black.opacity(0.06),
                    lineWidth: 1
                )
        }
    }

    private var placeholder: some View {
        Circle()
            .fill(ATHLTHTheme.accentSoft)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.38))
                    .foregroundStyle(ATHLTHTheme.accent)
            }
    }
}

struct CommunityGroupActivityPreviewCard: View {
    @EnvironmentObject private var groups: CommunityGroupStore

    var body: some View {
        ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Community Activity")
                        .font(.title3.weight(.bold))
                    Text("Updates from groups you belong to.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                NavigationLink {
                    CommunityGroupActivityCenterView()
                } label: {
                    Text("See All")
                        .font(.caption.weight(.semibold))
                }
            }

            if groups.communityActivity.isEmpty {
                Text(
                    "Group joins, updates, events and challenges will appear here."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 12)
            } else {
                VStack(spacing: 10) {
                    ForEach(
                        Array(groups.communityActivity.prefix(3))
                    ) { item in
                        CommunityGroupActivityRow(
                            item: item
                        )
                    }
                }
                .padding(.top, 12)
            }
        }
    }
}

struct CommunityGroupActivityCenterView: View {
    @EnvironmentObject private var groups: CommunityGroupStore

    var body: some View {
        List {
            if groups.communityActivity.isEmpty {
                ContentUnavailableView(
                    "No group activity yet",
                    systemImage: "bell.badge",
                    description: Text(
                        "Club activity will appear here."
                    )
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(groups.communityActivity) { item in
                    CommunityGroupActivityRow(
                        item: item
                    )
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Community Activity")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await groups.refresh()
        }
    }
}

private struct CommunityGroupActivityRow: View {
    @EnvironmentObject private var groups: CommunityGroupStore

    let item: CommunityGroupActivityRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(
                    tint.opacity(0.10),
                    in: RoundedRectangle(
                        cornerRadius: 11,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(item.headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                if let group = groups.group(
                    for: item.groupID
                ) {
                    Text(group.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let detail = item.detail,
                   !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 5) {
                    if let actorID = item.actorID,
                       let actor = groups.profileCard(
                           for: actorID
                       ) {
                        Text(actor.resolvedName)
                    }

                    Text(
                        item.createdAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer()
        }
    }

    private var icon: String {
        switch item.kind {
        case "member_joined":
            return "person.badge.plus"
        case "announcement":
            return "megaphone.fill"
        case "event_created":
            return "calendar.badge.plus"
        case "challenge_created":
            return "bolt.fill"
        default:
            return "bell.fill"
        }
    }

    private var tint: Color {
        switch item.kind {
        case "member_joined":
            return ATHLTHTheme.accent
        case "announcement":
            return .orange
        case "event_created":
            return ATHLTHTheme.recoveryBlue
        case "challenge_created":
            return .green
        default:
            return ATHLTHTheme.accent
        }
    }
}

struct CommunityGroupNotificationSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var groups: CommunityGroupStore

    let group: CommunityGroupRecord

    @State private var enabled = true
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Group notifications") {
                    Toggle(
                        "Notifications",
                        isOn: $enabled
                    )

                    Text(
                        enabled
                            ? "Receive Club post, chat, event and challenge notifications."
                            : "Group activity notifications are off."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section {
                    Label(
                        "Direct @mentions use your global Mentions setting in Settings → Notifications. Turning this group off does not disable a direct mention.",
                        systemImage: "at"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                enabled =
                    groups.notificationMode(
                        in: group.id
                    ) != "muted"
            }
            .onChange(of: enabled) {
                oldValue,
                newValue in

                guard oldValue != newValue else {
                    return
                }

                Task {
                    saving = true
                    let saved =
                        await groups.setGroupNotificationMode(
                            groupID: group.id,
                            mode:
                                newValue
                                    ? "all"
                                    : "muted"
                        )
                    saving = false

                    if !saved {
                        enabled = oldValue
                    }
                }
            }
            .disabled(saving)
        }
    }
}

struct CommunityGroupInviteMemberView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var groups: CommunityGroupStore
    @EnvironmentObject private var social: SocialStore

    let group: CommunityGroupRecord

    @State private var query = ""
    @State private var sendingIDs: Set<UUID> = []
    @State private var invitedIDs: Set<UUID> = []

    private var existingMemberIDs: Set<UUID> {
        Set(
            groups.members(in: group.id).map(\.userID)
        )
    }

    private var candidates: [SocialProfileCard] {
        let clean = query
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        let source =
            clean.isEmpty
                ? social.visibleProfiles
                : social.discoverResults

        return source
            .filter {
                !existingMemberIDs.contains($0.userID) &&
                $0.userID != social.currentUserID
            }
            .sorted {
                $0.resolvedName
                    .localizedCaseInsensitiveCompare(
                        $1.resolvedName
                    ) == .orderedAscending
            }
    }

    var body: some View {
        NavigationStack {
            List {
                if candidates.isEmpty {
                    ContentUnavailableView(
                        query.isEmpty
                            ? "Find people to invite"
                            : "No matching users",
                        systemImage: "person.badge.plus",
                        description: Text(
                            query.isEmpty
                                ? "Search by username or name."
                                : "Try another search."
                        )
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(candidates) { profile in
                        HStack(spacing: 12) {
                            CommunityGroupProfileAvatar(
                                profile: profile,
                                size: 42
                            )

                            VStack(
                                alignment: .leading,
                                spacing: 2
                            ) {
                                Text(profile.resolvedName)
                                    .font(
                                        .subheadline
                                            .weight(.semibold)
                                    )

                                if !profile.usernameLabel.isEmpty {
                                    Text(profile.usernameLabel)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            if invitedIDs.contains(
                                profile.userID
                            ) {
                                Label(
                                    "Invited",
                                    systemImage: "checkmark"
                                )
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(
                                    ATHLTHTheme.accentDeep
                                )
                            } else {
                                Button("Invite") {
                                    Task {
                                        sendingIDs.insert(
                                            profile.userID
                                        )

                                        let sent =
                                            await groups.inviteMember(
                                                groupID: group.id,
                                                userID:
                                                    profile.userID
                                            )

                                        sendingIDs.remove(
                                            profile.userID
                                        )

                                        if sent {
                                            invitedIDs.insert(
                                                profile.userID
                                            )
                                        }
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(
                                    sendingIDs.contains(
                                        profile.userID
                                    )
                                )
                            }
                        }
                    }
                }
            }
            .searchable(
                text: $query,
                prompt: "Search username or name"
            )
            .navigationTitle("Invite Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task(id: query) {
                let clean = query
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )

                guard clean.count >= 2 else {
                    social.clearSearch()
                    return
                }

                try? await Task.sleep(
                    for: .milliseconds(250)
                )
                guard !Task.isCancelled else {
                    return
                }

                await social.search(clean)
            }
            .onDisappear {
                social.clearSearch()
            }
        }
    }
}

struct CommunityGroupMembersView: View {
    @EnvironmentObject private var groups: CommunityGroupStore

    let group: CommunityGroupRecord

    @State private var showingInvite = false

    private var sortedMembers:
        [CommunityGroupMemberRecord] {
        groups.members(in: group.id).sorted {
            roleRank($0.role) < roleRank($1.role)
        }
    }

    private var currentGroup: CommunityGroupRecord {
        groups.group(for: group.id) ?? group
    }

    var body: some View {
        List {
            if groups.canManage(currentGroup) &&
                !groups.joinRequests(
                    in: group.id
                ).isEmpty {
                Section("Membership Requests") {
                    ForEach(
                        groups.joinRequests(
                            in: group.id
                        ),
                        id: \.userID
                    ) { request in
                        joinRequestRow(request)
                    }
                }
            }

            Section("Members") {
                ForEach(
                    sortedMembers,
                    id: \.userID
                ) { member in
                    memberRow(member)
                }
            }
        }
        .navigationTitle("Members")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if groups.canManage(currentGroup) {
                ToolbarItem(
                    placement: .topBarTrailing
                ) {
                    Button {
                        showingInvite = true
                    } label: {
                        Image(
                            systemName:
                                "person.badge.plus"
                        )
                    }
                    .accessibilityLabel(
                        "Invite group member"
                    )
                }
            }
        }
        .sheet(isPresented: $showingInvite) {
            CommunityGroupInviteMemberView(
                group: currentGroup
            )
        }
        .task {
            await groups.loadGroupContent(
                group.id
            )
        }
    }

    private func joinRequestRow(
        _ request: CommunityGroupJoinRequestRecord
    ) -> some View {
        HStack(spacing: 12) {
            if let profile = groups.profileCard(
                for: request.userID
            ) {
                CommunityGroupProfileAvatar(
                    profile: profile,
                    size: 42
                )

                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text(profile.resolvedName)
                        .font(
                            .subheadline
                                .weight(.semibold)
                        )

                    if !profile.usernameLabel.isEmpty {
                        Text(profile.usernameLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Image(
                    systemName:
                        "person.crop.circle.fill"
                )
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

                Text("ATHLTH member")
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )
            }

            Spacer()

            Button {
                Task {
                    _ = await groups
                        .respondToJoinRequest(
                            groupID: group.id,
                            userID: request.userID,
                            accept: false
                        )
                }
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.bordered)
            .tint(.secondary)

            Button {
                Task {
                    _ = await groups
                        .respondToJoinRequest(
                            groupID: group.id,
                            userID: request.userID,
                            accept: true
                        )
                }
            } label: {
                Image(systemName: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .tint(ATHLTHTheme.accentDeep)
        }
    }

    @ViewBuilder
    private func memberRow(
        _ member: CommunityGroupMemberRecord
    ) -> some View {
        HStack(spacing: 12) {
            if let profile = groups.profileCard(
                for: member.userID
            ) {
                CommunityGroupProfileAvatar(
                    profile: profile,
                    size: 42
                )

                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text(profile.resolvedName)
                        .font(
                            .subheadline
                                .weight(.semibold)
                        )

                    if let username =
                        profile.username {
                        Text("@\(username)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Image(
                    systemName:
                        "person.crop.circle.fill"
                )
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

                Text("Group member")
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )
            }

            Spacer()

            Text(roleTitle(member.role))
                .font(.caption2.weight(.bold))
                .foregroundStyle(
                    roleTint(member.role)
                )
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Color(
                        .secondarySystemGroupedBackground
                    ),
                    in: Capsule()
                )

            if groups.canManage(currentGroup) &&
                member.role != "owner" {
                Menu {
                    roleButton(
                        member,
                        role: "admin",
                        title: "Admin",
                        icon: "shield.fill"
                    )

                    roleButton(
                        member,
                        role: "contributor",
                        title: "Contributor",
                        icon: "megaphone.fill"
                    )

                    roleButton(
                        member,
                        role: "member",
                        title: "Member",
                        icon: "person.fill"
                    )

                    Divider()

                    Button(
                        "Remove from Group",
                        role: .destructive
                    ) {
                        Task {
                            _ = await groups.removeMember(
                                groupID: group.id,
                                userID: member.userID
                            )
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(
                            width: 30,
                            height: 30
                        )
                }
            }
        }
    }

    private func roleButton(
        _ member: CommunityGroupMemberRecord,
        role: String,
        title: String,
        icon: String
    ) -> some View {
        Button {
            Task {
                _ = await groups.setMemberRole(
                    groupID: group.id,
                    userID: member.userID,
                    role: role
                )
            }
        } label: {
            Label(
                title,
                systemImage:
                    member.role == role
                        ? "checkmark"
                        : icon
            )
        }
        .disabled(member.role == role)
    }

    private func roleRank(
        _ role: String
    ) -> Int {
        switch role {
        case "owner": return 0
        case "admin": return 1
        case "contributor": return 2
        default: return 3
        }
    }

    private func roleTitle(
        _ role: String
    ) -> String {
        switch role {
        case "owner": return "Owner"
        case "admin": return "Admin"
        case "contributor": return "Contributor"
        default: return "Member"
        }
    }

    private func roleTint(
        _ role: String
    ) -> Color {
        switch role {
        case "owner":
            return ATHLTHTheme.premiumGold
        case "admin":
            return ATHLTHTheme.accent
        case "contributor":
            return .orange
        default:
            return .secondary
        }
    }
}

private struct CommunityContentCoverPicker: View {
    @Binding var selectedPhoto: PhotosPickerItem?
    @Binding var imageData: Data?
    @Binding var selectedArtwork:
        ATHLTHStandardArtwork?

    let placeholderIcon: String

    @State private var imageError: String?
    @State private var cropRequest:
        CommunityImageCropRequest?

    var body: some View {
        let photoButtonTitle =
            imageData == nil
                ? "Upload Photo"
                : "Change Photo"

        return VStack(
            alignment: .leading,
            spacing: 12
        ) {
            Group {
                if let imageData,
                   let image = UIImage(data: imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if let selectedArtwork,
                          let image =
                            selectedArtwork
                                .resolvedUIImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(
                            1.16,
                            anchor: .trailing
                        )
                } else {
                    LinearGradient(
                        colors: [
                            ATHLTHTheme.accentDeep.opacity(0.18),
                            ATHLTHTheme.cardWarm,
                            ATHLTHTheme.canvasTop
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .overlay {
                        Image(systemName: placeholderIcon)
                            .font(
                                .system(
                                    size: 34,
                                    weight: .semibold
                                )
                            )
                            .foregroundStyle(
                                ATHLTHTheme.accentDeep
                                    .opacity(0.70)
                            )
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .clipped()
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
                .stroke(
                    ATHLTHTheme.border,
                    lineWidth: 1
                )
            }

            Text("ATHLTH images")
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )

            ATHLTHStandardArtworkPicker(
                selection: Binding(
                    get: {
                        selectedArtwork
                    },
                    set: { artwork in
                        selectedArtwork =
                            artwork
                        if artwork != nil {
                            selectedPhoto = nil
                            imageData = nil
                            imageError = nil
                        }
                    }
                )
            )

            HStack(spacing: 10) {
                PhotosPicker(
                    selection: $selectedPhoto,
                    matching: .images
                ) {
                    Label(
                        photoButtonTitle,
                        systemImage: "photo"
                    )
                }
                .buttonStyle(.bordered)

                if let imageData,
                   let image =
                    UIImage(
                        data: imageData
                    ) {
                    Button {
                        cropRequest =
                            CommunityImageCropRequest(
                                image: image,
                                target:
                                    .wideCover
                            )
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Crop",
                                norwegian: "Utsnitt"
                            ),
                            systemImage:
                                "crop"
                        )
                    }
                    .buttonStyle(.bordered)
                }

                if imageData != nil ||
                    selectedArtwork != nil {
                    Button(
                        "Remove",
                        role: .destructive
                    ) {
                        selectedPhoto = nil
                        imageData = nil
                        selectedArtwork = nil
                        imageError = nil
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()
            }

            if let imageError {
                Text(imageError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )
            } else {
                Text(
                    "Choose an ATHLTH image or upload your own. Uploaded photos are resized before upload."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
            }
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else {
                return
            }

            Task {
                do {
                    guard let data =
                            try await item
                                .loadTransferable(
                                    type:
                                        Data.self
                                )
                    else {
                        imageError =
                            "ATHLTH could not prepare that image."
                        selectedPhoto = nil
                        return
                    }

                    guard let prepared =
                            await CommunityImageProcessor
                                .prepareJPEG(
                                    data,
                                    maxPixelSize:
                                        2_400,
                                    quality: 0.92
                                ),
                          let image =
                            UIImage(
                                data:
                                    prepared
                            )
                    else {
                        imageError =
                            "ATHLTH could not prepare that image."
                        selectedPhoto = nil
                        return
                    }

                    selectedPhoto = nil
                    imageError = nil
                    cropRequest =
                        CommunityImageCropRequest(
                            image: image,
                            target:
                                .wideCover
                        )
                } catch {
                    selectedPhoto = nil
                    imageError =
                        error.localizedDescription
                }
            }
        }
        .fullScreenCover(
            item: $cropRequest
        ) { request in
            CommunityImageCropEditor(
                request: request
            ) { croppedData in
                imageData = croppedData
                selectedArtwork = nil
                imageError = nil
            }
        }
    }
}
struct CommunityGroupEventCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var groups:
        CommunityGroupStore

    let group: CommunityGroupRecord

    @State private var title = ""
    @State private var summary = ""
    @State private var startsAt =
        Date().addingTimeInterval(3600)
    @State private var meetingName = ""
    @State private var activityDraft =
        CommunityGroupActivityDraft()
    @State private var advancedOptions =
        CommunityGroupEventAdvancedOptions()
    @State private var cohostIDs: Set<UUID> = []
    @State private var selectedPhoto:
        PhotosPickerItem?
    @State private var imageData: Data?
    @State private var selectedArtwork:
        ATHLTHStandardArtwork?
    @State private var saving = false
    @State private var creationError: String?

    private var clubForest: Color {
        Color(red: 0.025, green: 0.30, blue: 0.21)
    }

    private var clubEmerald: Color {
        Color(red: 0.055, green: 0.49, blue: 0.32)
    }

    private var clubMint: Color {
        Color(red: 0.90, green: 0.96, blue: 0.92)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    eventCreationHero
                        .listRowInsets(
                            EdgeInsets()
                        )
                        .listRowBackground(
                            Color.clear
                        )
                }

                Section(
                    ATHLTHLocalization.choose(
                        english: "Cover image",
                        norwegian: "Toppbilde"
                    )
                ) {
                    CommunityContentCoverPicker(
                        selectedPhoto: $selectedPhoto,
                        imageData: $imageData,
                        selectedArtwork:
                            $selectedArtwork,
                        placeholderIcon:
                            "calendar.badge.plus"
                    )
                }

                Section(
                    ATHLTHLocalization.choose(
                        english: "Event",
                        norwegian: "Arrangement"
                    )
                ) {
                    TextField(
                        "Title",
                        text: $title
                    )

                    TextField(
                        "Description",
                        text: $summary,
                        axis: .vertical
                    )
                    .lineLimit(2...5)

                    DatePicker(
                        "Starts",
                        selection: $startsAt,
                        displayedComponents: [
                            .date,
                            .hourAndMinute
                        ]
                    )
                }

                CommunityGroupActivityEditor(
                    draft: $activityDraft
                )

                Section(
                    ATHLTHLocalization.choose(
                        english: "Meet",
                        norwegian: "Oppmøte"
                    )
                ) {
                    TextField(
                        "Meeting point (optional)",
                        text: $meetingName
                    )
                }

                CommunityGroupEventAdvancedEditor(
                    group: group,
                    eventStartsAt: startsAt,
                    options: $advancedOptions,
                    cohostIDs: $cohostIDs,
                    routeStart:
                        activityDraft
                            .configuration
                            .route?
                            .coordinates
                            .first
                )

                Section {
                    Label(
                        ATHLTHLocalization.format(
                            english: "Only members of %@ can see this event.",
                            norwegian: "Bare medlemmer av %@ kan se dette arrangementet.",
                            group.name
                        ),
                        systemImage: "lock.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(
                .hidden
            )
            .background(
                ATHLTHPremiumCanvas(
                    accent:
                        clubEmerald.opacity(
                            0.14
                        )
                )
                .ignoresSafeArea()
            )
            .tint(clubForest)
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english: "Create Event",
                    norwegian: "Opprett arrangement"
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .cancellationAction
                ) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Cancel",
                            norwegian: "Avbryt"
                        )
                    ) {
                        dismiss()
                    }
                    .foregroundStyle(
                        clubForest
                    )
                }

                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button(
                        saving
                            ? ATHLTHLocalization.choose(
                                english: "Creating…",
                                norwegian: "Oppretter…"
                            )
                            : ATHLTHLocalization.choose(
                                english: "Create",
                                norwegian: "Opprett"
                            )
                    ) {
                        createEvent()
                    }
                    .disabled(!canCreate)
                }
            }
            .alert(
                "Could Not Create Event",
                isPresented: Binding(
                    get: {
                        creationError != nil
                    },
                    set: {
                        if !$0 {
                            creationError = nil
                        }
                    }
                )
            ) {
                Button(
                    "OK",
                    role: .cancel
                ) {}
            } message: {
                Text(creationError ?? "")
            }
        }
    }

    private var eventCreationHero:
        some View {
        ZStack(alignment: .bottomLeading) {
            Image("CommunityHero")
                .resizable()
                .scaledToFill()
                .frame(height: 136)
                .frame(
                    maxWidth: .infinity
                )
                .clipped()

            LinearGradient(
                colors: [
                    Color.clear,
                    clubForest.opacity(0.84)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(
                alignment: .leading,
                spacing: 4
            ) {
                Label(
                    ATHLTHLocalization.choose(
                        english: "EVENT",
                        norwegian: "ARRANGEMENT"
                    ),
                    systemImage:
                        "calendar.badge.plus"
                )
                .font(
                    .caption2.bold()
                )
                .tracking(1.0)

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Bring the Club together",
                        norwegian:
                            "Samle fellesskapet"
                    )
                )
                .font(.title3.bold())

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Plan a session, place and route in one flow.",
                        norwegian:
                            "Planlegg økt, sted og rute i én flyt."
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    .white.opacity(0.88)
                )
            }
            .foregroundStyle(.white)
            .padding(15)
        }
        .frame(height: 136)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.22),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                clubForest.opacity(
                    0.12
                ),
            radius: 13,
            y: 6
        )
    }

    private var canCreate: Bool {
        !title
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .isEmpty &&
        activityDraft.validationMessage == nil &&
        !saving
    }

    private func createEvent() {
        if let validation =
            activityDraft.validationMessage {
            creationError = validation
            return
        }

        let configuration =
            activityDraft.configuration

        Task {
            saving = true

            let ok = await groups.createEvent(
                groupID: group.id,
                title: title,
                summary: summary,
                activityType:
                    configuration.activityType,
                startsAt: startsAt,
                meetingName: meetingName,
                imageData: imageData,
                imageReference:
                    selectedArtwork?
                        .reference,
                activityConfiguration:
                    configuration,
                advancedOptions:
                    advancedOptions,
                cohostIDs:
                    Array(cohostIDs)
            )

            saving = false

            if ok {
                dismiss()
            } else {
                creationError =
                    groups.errorMessage
                    ?? "ATHLTH could not create the event."
            }
        }
    }
}

private struct CommunityGroupChallengeTemplate:
    Identifiable,
    Hashable
{
    enum Category:
        String,
        CaseIterable,
        Identifiable
    {
        case running
        case movement
        case strength
        case consistency

        var id: String { rawValue }

        var title: String {
            switch self {
            case .running:
                return ATHLTHLocalization.choose(
                    english: "Running",
                    norwegian: "Løping"
                )
            case .movement:
                return ATHLTHLocalization.choose(
                    english: "Walk & Ride",
                    norwegian: "Gåtur & sykkel"
                )
            case .strength:
                return ATHLTHLocalization.choose(
                    english: "Strength",
                    norwegian: "Styrke"
                )
            case .consistency:
                return ATHLTHLocalization.choose(
                    english: "Club consistency",
                    norwegian: "Club-konsistens"
                )
            }
        }
    }

    let id: String
    let category: Category
    let titleEnglish: String
    let titleNorwegian: String
    let subtitleEnglish: String
    let subtitleNorwegian: String
    let icon: String
    let activityType: String
    let distanceKilometers: Double?
    let strengthDurationMinutes: Int?
    let goalPreset:
        CommunityGroupChallengeGoalPreset
    let target: Double
    let durationDays: Int
    let artwork: ATHLTHStandardArtwork

    var title: String {
        ATHLTHLocalization.choose(
            english: titleEnglish,
            norwegian: titleNorwegian
        )
    }

    var subtitle: String {
        ATHLTHLocalization.choose(
            english: subtitleEnglish,
            norwegian: subtitleNorwegian
        )
    }

    var durationLabel: String {
        ATHLTHLocalization.format(
            english:
                durationDays == 1
                    ? "%d day"
                    : "%d days",
            norwegian:
                durationDays == 1
                    ? "%d dag"
                    : "%d dager",
            durationDays
        )
    }

    var activityLabel: String {
        switch activityType {
        case "walking":
            return ATHLTHLocalization.choose(
                english: "Walk",
                norwegian: "Gåtur"
            )
        case "cycling":
            return ATHLTHLocalization.choose(
                english: "Cycling",
                norwegian: "Sykkel"
            )
        case "strength":
            return ATHLTHLocalization.choose(
                english: "Strength",
                norwegian: "Styrke"
            )
        default:
            return ATHLTHLocalization.choose(
                english: "Run",
                norwegian: "Løping"
            )
        }
    }

    static let clubTemplates:
        [CommunityGroupChallengeTemplate] = [
        .init(id: "club-distance-week", category: .running, titleEnglish: "Club Distance Week", titleNorwegian: "Club Distance Week", subtitleEnglish: "Add every qualifying run and see how far the Club can go together.", subtitleNorwegian: "Legg sammen alle løpeøktene og se hvor langt Club-en kommer.", icon: "figure.run", activityType: "running", distanceKilometers: 3, strengthDurationMinutes: nil, goalPreset: .mostDistance, target: 75, durationDays: 7, artwork: .running),
        .init(id: "relay-100", category: .running, titleEnglish: "100K Relay", titleNorwegian: "100K stafett", subtitleEnglish: "A social relay where every run moves the Club toward 100 km.", subtitleNorwegian: "En sosial stafett der hver løpetur flytter Club-en mot 100 km.", icon: "person.3.fill", activityType: "running", distanceKilometers: 2, strengthDurationMinutes: nil, goalPreset: .mostDistance, target: 100, durationDays: 7, artwork: .endurance),
        .init(id: "fastest-5k", category: .running, titleEnglish: "5K Speed Hunt", titleNorwegian: "5K Speed Hunt", subtitleEnglish: "Best verified 5 km attempt during the challenge window.", subtitleNorwegian: "Beste godkjente 5 km-forsøk i challenge-perioden.", icon: "timer", activityType: "running", distanceKilometers: 5, strengthDurationMinutes: nil, goalPreset: .fastestTime, target: 1, durationDays: 10, artwork: .sprint),
        .init(id: "fastest-10k", category: .running, titleEnglish: "10K Club Chase", titleNorwegian: "10K Club Chase", subtitleEnglish: "Give everyone time to put down their best 10 km effort.", subtitleNorwegian: "Gi alle tid til å sette sitt beste 10 km-forsøk.", icon: "stopwatch.fill", activityType: "running", distanceKilometers: 10, strengthDurationMinutes: nil, goalPreset: .fastestTime, target: 1, durationDays: 14, artwork: .progress),
        .init(id: "run-streak", category: .running, titleEnglish: "Run Streak League", titleNorwegian: "Løpestreak-liga", subtitleEnglish: "Most qualifying runs wins — short runs count too.", subtitleNorwegian: "Flest godkjente løpeturer vinner – korte turer teller også.", icon: "flame.fill", activityType: "running", distanceKilometers: 2, strengthDurationMinutes: nil, goalPreset: .mostCompletions, target: 1, durationDays: 14, artwork: .consistency),
        .init(id: "active-run-minutes", category: .running, titleEnglish: "Running Minutes Cup", titleNorwegian: "Løpeminutter-cup", subtitleEnglish: "A Club leaderboard based on active running minutes.", subtitleNorwegian: "Club-toppliste basert på aktive løpeminutter.", icon: "clock.fill", activityType: "running", distanceKilometers: 1, strengthDurationMinutes: nil, goalPreset: .mostActiveMinutes, target: 300, durationDays: 7, artwork: .endurance),
        .init(id: "walk-50", category: .movement, titleEnglish: "Walk Together 50K", titleNorwegian: "Walk Together 50K", subtitleEnglish: "A low-threshold Club challenge built around shared walking distance.", subtitleNorwegian: "En lavterskel Club-challenge med felles gådistanse.", icon: "figure.walk", activityType: "walking", distanceKilometers: 2, strengthDurationMinutes: nil, goalPreset: .mostDistance, target: 50, durationDays: 7, artwork: .walking),
        .init(id: "walking-streak", category: .movement, titleEnglish: "Daily Walk Crew", titleNorwegian: "Daily Walk Crew", subtitleEnglish: "Keep the group moving with as many qualifying walks as possible.", subtitleNorwegian: "Hold gruppen i bevegelse med flest mulig godkjente gåturer.", icon: "figure.walk.motion", activityType: "walking", distanceKilometers: 1.5, strengthDurationMinutes: nil, goalPreset: .mostCompletions, target: 1, durationDays: 7, artwork: .consistency),
        .init(id: "walk-active-minutes", category: .movement, titleEnglish: "Outdoor Minutes", titleNorwegian: "Utendørsminutter", subtitleEnglish: "Collect active walking minutes across the whole Club.", subtitleNorwegian: "Samle aktive gåminutter på tvers av hele Club-en.", icon: "sun.max.fill", activityType: "walking", distanceKilometers: 1, strengthDurationMinutes: nil, goalPreset: .mostActiveMinutes, target: 600, durationDays: 14, artwork: .adventure),
        .init(id: "ride-300", category: .movement, titleEnglish: "Ride 300", titleNorwegian: "Ride 300", subtitleEnglish: "A longer Club cycling challenge with cumulative distance.", subtitleNorwegian: "En lengre sykkelchallenge med samlet distanse.", icon: "bicycle", activityType: "cycling", distanceKilometers: 10, strengthDurationMinutes: nil, goalPreset: .mostDistance, target: 300, durationDays: 21, artwork: .adventure),
        .init(id: "weekend-ride", category: .movement, titleEnglish: "Weekend Ride-Off", titleNorwegian: "Weekend Ride-Off", subtitleEnglish: "Three days, one Club leaderboard, every kilometer counts.", subtitleNorwegian: "Tre dager, én Club-toppliste – hver kilometer teller.", icon: "bolt.fill", activityType: "cycling", distanceKilometers: 10, strengthDurationMinutes: nil, goalPreset: .mostDistance, target: 120, durationDays: 3, artwork: .sprint),
        .init(id: "strength-volume", category: .strength, titleEnglish: "Volume League", titleNorwegian: "Volumliga", subtitleEnglish: "Total completed strength volume across qualifying workouts.", subtitleNorwegian: "Samlet styrkevolum fra godkjente styrkeøkter.", icon: "dumbbell.fill", activityType: "strength", distanceKilometers: nil, strengthDurationMinutes: 35, goalPreset: .strengthVolume, target: 50000, durationDays: 7, artwork: .strength),
        .init(id: "rep-race", category: .strength, titleEnglish: "Rep Race", titleNorwegian: "Rep Race", subtitleEnglish: "Build Club energy around total completed repetitions.", subtitleNorwegian: "Bygg Club-energi rundt totalt antall gjennomførte repetisjoner.", icon: "repeat", activityType: "strength", distanceKilometers: nil, strengthDurationMinutes: 30, goalPreset: .strengthReps, target: 750, durationDays: 7, artwork: .strength),
        .init(id: "heavy-hitters", category: .strength, titleEnglish: "Heavy Hitters", titleNorwegian: "Heavy Hitters", subtitleEnglish: "Best qualifying lift wins — ideal for a Club strength week.", subtitleNorwegian: "Beste godkjente løft vinner – perfekt for en styrkeuke i Club-en.", icon: "scalemass.fill", activityType: "strength", distanceKilometers: nil, strengthDurationMinutes: 30, goalPreset: .heaviestWeight, target: 100, durationDays: 7, artwork: .progress),
        .init(id: "strength-attendance", category: .strength, titleEnglish: "Gym Attendance Cup", titleNorwegian: "Gym Attendance Cup", subtitleEnglish: "Most completed strength sessions takes the Club crown.", subtitleNorwegian: "Flest gjennomførte styrkeøkter tar Club-kronen.", icon: "checkmark.seal.fill", activityType: "strength", distanceKilometers: nil, strengthDurationMinutes: 25, goalPreset: .mostCompletions, target: 1, durationDays: 14, artwork: .consistency),
        .init(id: "strength-minutes", category: .strength, titleEnglish: "Iron Minutes", titleNorwegian: "Iron Minutes", subtitleEnglish: "Compete on active strength-training time instead of kilos.", subtitleNorwegian: "Konkurrer på aktiv styrketid i stedet for kilo.", icon: "clock.fill", activityType: "strength", distanceKilometers: nil, strengthDurationMinutes: 20, goalPreset: .mostActiveMinutes, target: 300, durationDays: 7, artwork: .endurance),
        .init(id: "seven-day-consistency", category: .consistency, titleEnglish: "7-Day Consistency", titleNorwegian: "7-dagers konsistens", subtitleEnglish: "A simple run-based attendance challenge for the whole Club.", subtitleNorwegian: "En enkel løpebasert oppmøte-challenge for hele Club-en.", icon: "calendar.badge.checkmark", activityType: "running", distanceKilometers: 1, strengthDurationMinutes: nil, goalPreset: .mostCompletions, target: 1, durationDays: 7, artwork: .consistency),
        .init(id: "fourteen-day-consistency", category: .consistency, titleEnglish: "14-Day Crew", titleNorwegian: "14-Day Crew", subtitleEnglish: "A longer consistency battle where repeated participation matters.", subtitleNorwegian: "En lengre konsistenskamp der jevn deltakelse teller.", icon: "person.3.fill", activityType: "walking", distanceKilometers: 1, strengthDurationMinutes: nil, goalPreset: .mostCompletions, target: 1, durationDays: 14, artwork: .walking),
        .init(id: "club-endurance-month", category: .consistency, titleEnglish: "Club Endurance Month", titleNorwegian: "Club Endurance Month", subtitleEnglish: "A month-long cumulative running distance challenge.", subtitleNorwegian: "En månedslang challenge med samlet løpedistanse.", icon: "calendar", activityType: "running", distanceKilometers: 2, strengthDurationMinutes: nil, goalPreset: .mostDistance, target: 250, durationDays: 30, artwork: .endurance),
        .init(id: "mountain-movement", category: .consistency, titleEnglish: "Adventure Crew", titleNorwegian: "Adventure Crew", subtitleEnglish: "Use walking sessions to create a social outdoor distance league.", subtitleNorwegian: "Bruk gåturer til å lage en sosial utendørs distanseliga.", icon: "mountain.2.fill", activityType: "walking", distanceKilometers: 3, strengthDurationMinutes: nil, goalPreset: .mostDistance, target: 80, durationDays: 14, artwork: .mountain)
    ]
}

private struct CommunityGroupChallengeTemplatePicker:
    View
{
    @Environment(\.dismiss) private var dismiss

    let selectedID: String?
    let onSelect:
        (CommunityGroupChallengeTemplate) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                ATHLTHPremiumCanvas(
                    accent:
                        ATHLTHTheme
                            .premiumGold
                            .opacity(0.18)
                )

                ScrollView {
                    LazyVStack(
                        alignment: .leading,
                        spacing: 18
                    ) {
                        VStack(
                            alignment: .leading,
                            spacing: 6
                        ) {
                            Text(
                                ATHLTHLocalization.choose(
                                    english: "Built for Clubs",
                                    norwegian: "Laget for Club"
                                )
                            )
                            .font(.title2.weight(.bold))

                            Text(
                                ATHLTHLocalization.choose(
                                    english:
                                        "These are Club-only templates focused on participation, leaderboards and shared momentum — separate from ATHLTH's general challenges.",
                                    norwegian:
                                        "Dette er egne Club-maler for deltakelse, topplister og felles momentum – adskilt fra de generelle ATHLTH-challengene."
                                )
                            )
                            .font(.subheadline)
                            .foregroundStyle(
                                ATHLTHTheme.mutedText
                            )
                        }

                        ForEach(
                            CommunityGroupChallengeTemplate
                                .Category.allCases
                        ) { category in
                            let templates =
                                CommunityGroupChallengeTemplate
                                    .clubTemplates
                                    .filter {
                                        $0.category == category
                                    }

                            VStack(
                                alignment: .leading,
                                spacing: 10
                            ) {
                                Text(category.title)
                                    .font(.headline.weight(.bold))

                                ForEach(templates) {
                                    template in
                                    Button {
                                        onSelect(template)
                                        dismiss()
                                    } label: {
                                        HStack(spacing: 13) {
                                            Image(
                                                systemName:
                                                    template.icon
                                            )
                                            .font(
                                                .system(
                                                    size: 18,
                                                    weight: .semibold
                                                )
                                            )
                                            .foregroundStyle(.white)
                                            .frame(
                                                width: 42,
                                                height: 42
                                            )
                                            .background(
                                                LinearGradient(
                                                    colors: [
                                                        ATHLTHTheme
                                                            .accentDeep,
                                                        ATHLTHTheme
                                                            .premiumGold
                                                    ],
                                                    startPoint:
                                                        .topLeading,
                                                    endPoint:
                                                        .bottomTrailing
                                                ),
                                                in:
                                                    RoundedRectangle(
                                                        cornerRadius: 13,
                                                        style: .continuous
                                                    )
                                            )

                                            VStack(
                                                alignment: .leading,
                                                spacing: 3
                                            ) {
                                                Text(template.title)
                                                    .font(
                                                        .subheadline
                                                            .weight(.bold)
                                                    )
                                                    .foregroundStyle(
                                                        ATHLTHTheme
                                                            .primaryText
                                                    )

                                                Text(template.subtitle)
                                                    .font(.caption)
                                                    .foregroundStyle(
                                                        ATHLTHTheme
                                                            .mutedText
                                                    )
                                                    .lineLimit(2)

                                                HStack(spacing: 8) {
                                                    Text(
                                                        template
                                                            .activityLabel
                                                    )
                                                    Text(
                                                        template
                                                            .durationLabel
                                                    )
                                                }
                                                .font(
                                                    .caption2
                                                        .weight(.semibold)
                                                )
                                                .foregroundStyle(
                                                    ATHLTHTheme
                                                        .accentDeep
                                                )
                                            }

                                            Spacer()

                                            Image(
                                                systemName:
                                                    selectedID ==
                                                        template.id
                                                        ? "checkmark.circle.fill"
                                                        : "chevron.right"
                                            )
                                            .foregroundStyle(
                                                selectedID ==
                                                    template.id
                                                    ? ATHLTHTheme
                                                        .premiumGold
                                                    : Color.secondary
                                            )
                                        }
                                        .padding(13)
                                        .background(
                                            ATHLTHTheme.card,
                                            in:
                                                RoundedRectangle(
                                                    cornerRadius: 18,
                                                    style: .continuous
                                                )
                                        )
                                        .overlay {
                                            RoundedRectangle(
                                                cornerRadius: 18,
                                                style: .continuous
                                            )
                                            .stroke(
                                                selectedID ==
                                                    template.id
                                                    ? ATHLTHTheme
                                                        .premiumGold
                                                        .opacity(0.48)
                                                    : ATHLTHTheme
                                                        .premiumGold
                                                        .opacity(0.12),
                                                lineWidth:
                                                    selectedID ==
                                                        template.id
                                                        ? 1.3
                                                        : 0.8
                                            )
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                }
            }
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english:
                        "Club Challenge Templates",
                    norwegian:
                        "Club-maler"
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Done",
                            norwegian: "Ferdig"
                        )
                    ) {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct CommunityGroupChallengeCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var groups:
        CommunityGroupStore

    let group: CommunityGroupRecord

    @State private var title = ""
    @State private var summary = ""
    @State private var goalPreset:
        CommunityGroupChallengeGoalPreset =
            .mostDistance
    @State private var metric:
        CommunityGroupChallengeMetric = .distanceKM
    @State private var target = "100"
    @State private var startsAt = Date()
    @State private var endsAt =
        Calendar.current.date(
            byAdding: .day,
            value: 7,
            to: Date()
        ) ?? Date().addingTimeInterval(604800)
    @State private var activityDraft =
        CommunityGroupActivityDraft()
    @State private var challengeOptions =
        CommunityGroupChallengeAdvancedOptions()
    @State private var challengeCohostIDs:
        Set<UUID> = []
    @State private var selectedPhoto:
        PhotosPickerItem?
    @State private var imageData: Data?
    @State private var selectedArtwork:
        ATHLTHStandardArtwork?
    @State private var selectedTemplateID:
        String?
    @State private var showingTemplatePicker = false
    @State private var saving = false
    @State private var creationError: String?

    private var targetValue: Double? {
        Double(
            target
                .replacingOccurrences(
                    of: ",",
                    with: "."
                )
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                if groups.canManage(group) {
                    Section {
                        Button {
                            showingTemplatePicker = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(
                                    systemName:
                                        "rectangle.stack.badge.plus"
                                )
                                .font(
                                    .system(
                                        size: 18,
                                        weight: .semibold
                                    )
                                )
                                .foregroundStyle(.white)
                                .frame(
                                    width: 40,
                                    height: 40
                                )
                                .background(
                                    LinearGradient(
                                        colors: [
                                            ATHLTHTheme
                                                .accentDeep,
                                            ATHLTHTheme
                                                .premiumGold
                                        ],
                                        startPoint:
                                            .topLeading,
                                        endPoint:
                                            .bottomTrailing
                                    ),
                                    in:
                                        RoundedRectangle(
                                            cornerRadius: 12,
                                            style: .continuous
                                        )
                                )

                                VStack(
                                    alignment: .leading,
                                    spacing: 2
                                ) {
                                    Text(
                                        selectedTemplateID
                                            .flatMap {
                                                id in
                                                CommunityGroupChallengeTemplate
                                                    .clubTemplates
                                                    .first {
                                                        $0.id == id
                                                    }?
                                                    .title
                                            } ??
                                        ATHLTHLocalization
                                            .choose(
                                                english:
                                                    "Choose a Club template",
                                                norwegian:
                                                    "Velg en Club-mal"
                                            )
                                    )
                                    .font(
                                        .subheadline
                                            .weight(.semibold)
                                    )
                                    .foregroundStyle(
                                        ATHLTHTheme.primaryText
                                    )

                                    Text(
                                        ATHLTHLocalization.choose(
                                            english:
                                                "20 ready-made Club challenges",
                                            norwegian:
                                                "20 ferdige Club-challenges"
                                        )
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(
                                    systemName: "chevron.right"
                                )
                                .font(.caption.bold())
                                .foregroundStyle(
                                    ATHLTHTheme.premiumGold
                                )
                            }
                        }
                        .buttonStyle(.plain)

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Club templates are separate from ATHLTH's general challenges. Selecting one fills in activity, scoring, target, duration and artwork — and everything stays editable.",
                                norwegian:
                                    "Club-malene er adskilt fra de generelle ATHLTH-challengene. En mal fyller inn aktivitet, poengberegning, mål, varighet og bilde – og alt kan fortsatt redigeres."
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } header: {
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Start from Club template",
                                norwegian:
                                    "Start fra Club-mal"
                            )
                        )
                    }
                }

                Section("Cover image") {
                    CommunityContentCoverPicker(
                        selectedPhoto: $selectedPhoto,
                        imageData: $imageData,
                        selectedArtwork:
                            $selectedArtwork,
                        placeholderIcon: "bolt.fill"
                    )
                }

                Section("Challenge") {
                    TextField(
                        "Title",
                        text: $title
                    )

                    TextField(
                        "Description",
                        text: $summary,
                        axis: .vertical
                    )
                    .lineLimit(2...5)
                }

                CommunityGroupActivityEditor(
                    draft: $activityDraft
                )
                .onChange(
                    of: activityDraft.activityType
                ) { _, type in
                    if type == "strength" {
                        goalPreset = .strengthVolume
                        target = "5000"
                    } else if [
                        CommunityGroupChallengeGoalPreset
                            .strengthVolume,
                        .heaviestWeight,
                        .strengthReps
                    ].contains(goalPreset) {
                        goalPreset = .mostDistance
                        target = "100"
                    }

                    applyGoalPreset(goalPreset)
                }

                Section("Goal") {
                    Picker(
                        "Challenge goal",
                        selection: $goalPreset
                    ) {
                        ForEach(
                            suggestedGoalPresets
                        ) { preset in
                            Text(preset.title)
                                .tag(preset)
                        }
                    }
                    .onChange(
                        of: goalPreset
                    ) { _, preset in
                        applyGoalPreset(preset)
                    }

                    if goalNeedsTarget {
                        HStack {
                            TextField(
                                "Target",
                                text: $target
                            )
                            .keyboardType(
                                .decimalPad
                            )

                            Text(metric.unit)
                                .foregroundStyle(
                                    .secondary
                                )
                        }
                    } else {
                        LabeledContent(
                            "Scoring",
                            value:
                                challengeOptions
                                    .scoringMode
                                    .title
                        )
                    }

                    Text(goalExplanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    if startsAt >
                        Date()
                            .addingTimeInterval(
                                60
                            ) {
                        Label(
                            ATHLTHLocalization.format(
                                english:
                                    "Planned · starts %@",
                                norwegian:
                                    "Planlagt · starter %@",
                                startsAt.formatted(
                                    date:
                                        .abbreviated,
                                    time:
                                        .shortened
                                )
                            ),
                            systemImage:
                                "calendar.badge.clock"
                        )
                        .font(
                            .subheadline
                                .weight(
                                    .semibold
                                )
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .accentDeep
                        )
                    } else {
                        Label(
                            ATHLTHLocalization.choose(
                                english:
                                    "Starts now",
                                norwegian:
                                    "Starter nå"
                            ),
                            systemImage:
                                "bolt.fill"
                        )
                        .font(
                            .subheadline
                                .weight(
                                    .semibold
                                )
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .accentDeep
                        )
                    }

                    ScrollView(
                        .horizontal,
                        showsIndicators: false
                    ) {
                        HStack(spacing: 8) {
                            challengeStartShortcut(
                                title:
                                    ATHLTHLocalization
                                        .choose(
                                            english:
                                                "Now",
                                            norwegian:
                                                "Nå"
                                        ),
                                days: 0
                            )
                            challengeStartShortcut(
                                title:
                                    ATHLTHLocalization
                                        .choose(
                                            english:
                                                "Tomorrow",
                                            norwegian:
                                                "I morgen"
                                        ),
                                days: 1
                            )
                            challengeStartShortcut(
                                title:
                                    ATHLTHLocalization
                                        .choose(
                                            english:
                                                "+1 week",
                                            norwegian:
                                                "+1 uke"
                                        ),
                                days: 7
                            )
                            challengeStartShortcut(
                                title:
                                    ATHLTHLocalization
                                        .choose(
                                            english:
                                                "+2 weeks",
                                            norwegian:
                                                "+2 uker"
                                        ),
                                days: 14
                            )
                        }
                    }

                    DatePicker(
                        ATHLTHLocalization.choose(
                            english: "Starts",
                            norwegian: "Starter"
                        ),
                        selection: $startsAt,
                        displayedComponents: [
                            .date,
                            .hourAndMinute
                        ]
                    )
                    .onChange(
                        of: startsAt
                    ) { oldValue, newValue in
                        if endsAt <= newValue {
                            let oldDuration =
                                max(
                                    endsAt
                                        .timeIntervalSince(
                                            oldValue
                                        ),
                                    7 * 86_400
                                )
                            endsAt =
                                newValue
                                    .addingTimeInterval(
                                        oldDuration
                                    )
                        }
                    }

                    DatePicker(
                        ATHLTHLocalization.choose(
                            english: "Ends",
                            norwegian: "Slutter"
                        ),
                        selection: $endsAt,
                        in: startsAt...,
                        displayedComponents: [
                            .date,
                            .hourAndMinute
                        ]
                    )

                    HStack(spacing: 8) {
                        ForEach(
                            [3, 7, 14, 30],
                            id: \.self
                        ) { days in
                            Button {
                                setChallengeDuration(
                                    days: days
                                )
                            } label: {
                                Text(
                                    ATHLTHLocalization.format(
                                        english:
                                            "%dd",
                                        norwegian:
                                            "%d d",
                                        days
                                    )
                                )
                                .font(
                                    .caption.weight(
                                        .semibold
                                    )
                                )
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .accentDeep
                                )
                                .padding(
                                    .horizontal,
                                    10
                                )
                                .padding(
                                    .vertical,
                                    7
                                )
                                .background(
                                    ATHLTHTheme
                                        .champagneSoft,
                                    in: Capsule()
                                )
                            }
                            .buttonStyle(
                                .plain
                            )
                        }
                    }

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "You can create several future challenges. They stay under Planned until their start time and then become active automatically.",
                            norwegian:
                                "Du kan opprette flere challenges fremover. De ligger under Planlagte frem til starttidspunktet og blir aktive automatisk."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )
                } header: {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Schedule",
                            norwegian:
                                "Planlegging"
                        )
                    )
                }

                CommunityGroupChallengeAdvancedEditor(
                    group: group,
                    options: $challengeOptions,
                    cohostIDs:
                        $challengeCohostIDs,
                    routeSelected:
                        activityDraft.mode ==
                            .route &&
                        (
                            activityDraft
                                .selectedRoute != nil ||
                            activityDraft
                                .selectedRouteSnapshot != nil
                        )
                )

                Section {
                    Label(
                        "Only completed workouts matching the selected activity contribute to this challenge. The same workout is counted once.",
                        systemImage: "bolt.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Group Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .cancellationAction
                ) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button(
                        saving
                            ? "Creating…"
                            : "Create"
                    ) {
                        createChallenge()
                    }
                    .disabled(!canCreate)
                }
            }
            .sheet(
                isPresented:
                    $showingTemplatePicker
            ) {
                CommunityGroupChallengeTemplatePicker(
                    selectedID:
                        selectedTemplateID
                ) { template in
                    applyTemplate(template)
                }
            }
            .alert(
                "Could Not Create Challenge",
                isPresented: Binding(
                    get: {
                        creationError != nil
                    },
                    set: {
                        if !$0 {
                            creationError = nil
                        }
                    }
                )
            ) {
                Button(
                    "OK",
                    role: .cancel
                ) {}
            } message: {
                Text(creationError ?? "")
            }
        }
    }

    private func challengeStartShortcut(
        title: String,
        days: Int
    ) -> some View {
        Button {
            let currentDuration =
                max(
                    endsAt
                        .timeIntervalSince(
                            startsAt
                        ),
                    86_400
                )

            let newStart: Date

            if days == 0 {
                newStart = Date()
            } else {
                newStart =
                    Calendar.current.date(
                        byAdding: .day,
                        value: days,
                        to: Date()
                    ) ??
                    Date().addingTimeInterval(
                        TimeInterval(days) *
                            86_400
                    )
            }

            startsAt = newStart
            endsAt =
                newStart.addingTimeInterval(
                    currentDuration
                )
        } label: {
            Text(title)
                .font(
                    .caption.weight(
                        .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .accentDeep
                )
                .padding(
                    .horizontal,
                    11
                )
                .padding(
                    .vertical,
                    7
                )
                .background(
                    ATHLTHTheme
                        .cardWarm,
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(
                            ATHLTHTheme
                                .premiumGold
                                .opacity(
                                    0.16
                                ),
                            lineWidth: 0.8
                        )
                }
        }
        .buttonStyle(.plain)
    }

    private func setChallengeDuration(
        days: Int
    ) {
        endsAt =
            Calendar.current.date(
                byAdding: .day,
                value: days,
                to: startsAt
            ) ??
            startsAt.addingTimeInterval(
                TimeInterval(days) *
                    86_400
            )
    }

    private func applyTemplate(
        _ template:
            CommunityGroupChallengeTemplate
    ) {
        selectedTemplateID = template.id
        title = template.title
        summary = template.subtitle

        var draft =
            CommunityGroupActivityDraft()
        draft.activityType =
            template.activityType
        draft.mode =
            template.activityType == "strength"
                ? .strength
                : .free

        if let distance =
                template.distanceKilometers {
            draft.distanceText =
                String(
                    format: "%.1f",
                    distance
                )
        }

        if let minutes =
                template
                    .strengthDurationMinutes {
            draft.strengthDurationText =
                String(minutes)
        }

        activityDraft = draft
        goalPreset = template.goalPreset
        metric = template.goalPreset.metric
        target =
            String(
                format: "%.1f",
                template.target
            )
        challengeOptions.scoringMode =
            template.goalPreset.scoringMode

        startsAt = Date()
        endsAt =
            Calendar.current.date(
                byAdding: .day,
                value: template.durationDays,
                to: startsAt
            ) ??
            startsAt.addingTimeInterval(
                TimeInterval(
                    template.durationDays
                ) * 86_400
            )

        selectedArtwork = template.artwork
        selectedPhoto = nil
        imageData = nil
    }

    private var canCreate: Bool {
        !title
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .isEmpty &&
        resolvedTargetValue > 0 &&
        endsAt > startsAt &&
        activityDraft.validationMessage == nil &&
        !saving
    }

    private func createChallenge() {
        if goalNeedsTarget &&
            (targetValue ?? 0) <= 0 {
            creationError =
                "Choose a valid challenge target."
            return
        }

        if let validation =
            activityDraft.validationMessage {
            creationError = validation
            return
        }

        let configuration =
            activityDraft.configuration

        Task {
            saving = true

            let ok = await groups.createChallenge(
                groupID: group.id,
                title: title,
                summary: summary,
                metric: metric,
                targetValue:
                    resolvedTargetValue,
                startsAt: startsAt,
                endsAt: endsAt,
                imageData: imageData,
                imageReference:
                    selectedArtwork?
                        .reference,
                activityConfiguration:
                    configuration,
                advancedOptions:
                    challengeOptions,
                cohostIDs:
                    Array(challengeCohostIDs)
            )

            saving = false

            if ok {
                dismiss()
            } else {
                creationError =
                    groups.errorMessage
                    ?? "ATHLTH could not create the challenge."
            }
        }
    }

    private var suggestedGoalPresets:
        [CommunityGroupChallengeGoalPreset] {
        switch activityDraft.activityType {
        case "strength":
            return [
                .strengthVolume,
                .heaviestWeight,
                .strengthReps,
                .mostCompletions,
                .mostActiveMinutes,
                .completeTarget
            ]
        default:
            return [
                .fastestTime,
                .mostDistance,
                .mostCompletions,
                .mostActiveMinutes,
                .completeTarget
            ]
        }
    }

    private var goalNeedsTarget: Bool {
        switch goalPreset {
        case .mostDistance,
             .mostActiveMinutes,
             .strengthVolume,
             .heaviestWeight,
             .strengthReps:
            return true
        case .fastestTime,
             .mostCompletions,
             .completeTarget:
            return false
        }
    }

    private var resolvedTargetValue: Double {
        goalNeedsTarget
            ? (targetValue ?? 0)
            : 1
    }

    private var goalExplanation: String {
        switch goalPreset {
        case .fastestTime:
            return "The fastest qualifying attempt wins. For a fixed distance ATHLTH can verify the fastest GPS segment."
        case .mostDistance:
            return "All qualifying distance is added during the challenge window."
        case .mostCompletions:
            return "Each qualifying workout counts as one completion."
        case .mostActiveMinutes:
            return "Active workout minutes are added across qualifying attempts."
        case .strengthVolume:
            return "Completed reps × weight are added across qualifying strength workouts."
        case .heaviestWeight:
            return "The heaviest completed weight in a qualifying strength workout counts."
        case .strengthReps:
            return "Completed reps are added across qualifying strength workouts."
        case .completeTarget:
            return "Participants complete the configured activity target. Progress stops at completion."
        }
    }

    private func applyGoalPreset(
        _ preset:
            CommunityGroupChallengeGoalPreset
    ) {
        metric = preset.metric
        challengeOptions.scoringMode =
            preset.scoringMode

        if !goalNeedsTarget {
            target = "1"
        } else if targetValue == nil ||
                    (targetValue ?? 0) <= 0 {
            target = "100"
        }
    }

}
