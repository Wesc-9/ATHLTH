import AVFoundation
import Combine
import CoreMotion
import SwiftUI
import UIKit

@MainActor
final class AchievementTiltMotionStore:
    ObservableObject
{
    static let shared =
        AchievementTiltMotionStore()

    @Published private(set) var x: Double = 0
    @Published private(set) var y: Double = 0

    private let manager =
        CMMotionManager()
    private var observers = 0

    private init() {
        manager
            .deviceMotionUpdateInterval =
            1.0 / 20.0
    }

    func begin() {
        observers += 1

        guard observers == 1,
              manager
                .isDeviceMotionAvailable
        else {
            return
        }

        manager
            .startDeviceMotionUpdates(
                to: .main
            ) { [weak self] motion, _ in
                guard let self,
                      let motion
                else {
                    return
                }

                let roll =
                    max(
                        -1,
                        min(
                            1,
                            motion.attitude.roll /
                                0.75
                        )
                    )
                let pitch =
                    max(
                        -1,
                        min(
                            1,
                            motion.attitude.pitch /
                                0.75
                        )
                    )

                self.x = roll
                self.y = pitch
            }
    }

    func end() {
        observers =
            max(
                observers - 1,
                0
            )

        guard observers == 0
        else {
            return
        }

        manager
            .stopDeviceMotionUpdates()
        x = 0
        y = 0
    }
}

extension TrophyRarity {
    /// Restrained ATHLTH material system.
    ///
    /// Rarity is communicated primarily through finish, contrast and light
    /// rather than a rainbow of category colours:
    /// Core = matte graphite, Rare = titanium, Epic = carbon + warm metal,
    /// Signature = black + gold.
    var achievementPalette:
        [Color]
    {
        switch self {
        case .core:
            return [
                Color(
                    red: 0.31,
                    green: 0.33,
                    blue: 0.36
                ),
                Color(
                    red: 0.16,
                    green: 0.17,
                    blue: 0.19
                ),
                Color(
                    red: 0.075,
                    green: 0.08,
                    blue: 0.09
                )
            ]

        case .rare:
            return [
                Color(
                    red: 0.94,
                    green: 0.95,
                    blue: 0.96
                ),
                Color(
                    red: 0.64,
                    green: 0.66,
                    blue: 0.69
                ),
                Color(
                    red: 0.25,
                    green: 0.27,
                    blue: 0.30
                ),
                Color(
                    red: 0.82,
                    green: 0.84,
                    blue: 0.86
                )
            ]

        case .epic:
            return [
                Color(
                    red: 0.35,
                    green: 0.33,
                    blue: 0.29
                ),
                Color(
                    red: 0.17,
                    green: 0.16,
                    blue: 0.15
                ),
                ATHLTHTheme
                    .premiumGold
                    .opacity(0.82),
                Color(
                    red: 0.065,
                    green: 0.065,
                    blue: 0.07
                )
            ]

        case .signature:
            return [
                Color(
                    red: 0.035,
                    green: 0.035,
                    blue: 0.04
                ),
                Color(
                    red: 0.12,
                    green: 0.105,
                    blue: 0.075
                ),
                ATHLTHTheme
                    .premiumGold,
                Color(
                    red: 0.055,
                    green: 0.055,
                    blue: 0.06
                )
            ]
        }
    }

    var progressPalette:
        [Color]
    {
        switch self {
        case .core:
            return [
                Color(
                    red: 0.37,
                    green: 0.40,
                    blue: 0.44
                ),
                Color(
                    red: 0.67,
                    green: 0.69,
                    blue: 0.72
                )
            ]

        case .rare:
            return [
                Color(
                    red: 0.54,
                    green: 0.57,
                    blue: 0.61
                ),
                Color.white
                    .opacity(0.92)
            ]

        case .epic:
            return [
                Color(
                    red: 0.28,
                    green: 0.27,
                    blue: 0.25
                ),
                ATHLTHTheme
                    .premiumGold
                    .opacity(0.88)
            ]

        case .signature:
            return [
                ATHLTHTheme
                    .premiumGold
                    .opacity(0.82),
                Color.white
                    .opacity(0.96)
            ]
        }
    }

    var particlePalette:
        [Color]
    {
        switch self {
        case .core:
            return [
                Color.white
                    .opacity(0.78),
                Color(
                    red: 0.48,
                    green: 0.51,
                    blue: 0.55
                )
            ]

        case .rare:
            return [
                Color.white,
                Color(
                    red: 0.69,
                    green: 0.71,
                    blue: 0.74
                ),
                Color(
                    red: 0.43,
                    green: 0.46,
                    blue: 0.50
                )
            ]

        case .epic:
            return [
                Color.white
                    .opacity(0.92),
                ATHLTHTheme
                    .premiumGold,
                Color(
                    red: 0.40,
                    green: 0.38,
                    blue: 0.34
                )
            ]

        case .signature:
            return [
                Color.white,
                ATHLTHTheme
                    .premiumGold,
                Color(
                    red: 0.63,
                    green: 0.56,
                    blue: 0.39
                )
            ]
        }
    }

    var unlockParticleCount:
        Int
    {
        switch self {
        case .core:
            return 14
        case .rare:
            return 20
        case .epic:
            return 28
        case .signature:
            return 36
        }
    }

    var unlockBurstRadius:
        CGFloat
    {
        switch self {
        case .core:
            return 112
        case .rare:
            return 138
        case .epic:
            return 166
        case .signature:
            return 198
        }
    }
}

struct AchievementProgressRing:
    View
{
    let progress: Double
    let rarity: TrophyRarity
    var lineWidth: CGFloat = 4

    private var normalized:
        Double
    {
        min(
            max(
                progress,
                0
            ),
            1
        )
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    Color.white
                        .opacity(0.16),
                    lineWidth:
                        lineWidth
                )

            Circle()
                .trim(
                    from: 0,
                    to: normalized
                )
                .stroke(
                    AngularGradient(
                        colors:
                            rarity
                                .progressPalette,
                        center: .center
                    ),
                    style:
                        StrokeStyle(
                            lineWidth:
                                lineWidth,
                            lineCap:
                                .round
                        )
                )
                .rotationEffect(
                    .degrees(-90)
                )

            Text(
                "\(Int((normalized * 100).rounded()))"
            )
            .font(
                .system(
                    size: 8,
                    weight: .bold,
                    design: .rounded
                )
            )
            .foregroundStyle(
                .white
            )
        }
        .accessibilityLabel(
            "Progress"
        )
        .accessibilityValue(
            "\(Int((normalized * 100).rounded())) percent"
        )
    }
}

struct AchievementParticleBurst:
    View
{
    let rarity: TrophyRarity
    var reduced = false

    @State private var burst = false

    private var particleCount: Int {
        reduced
            ? max(
                rarity
                    .unlockParticleCount / 2,
                8
            )
            : rarity
                .unlockParticleCount
    }

    private var burstRadius: CGFloat {
        reduced
            ? rarity
                .unlockBurstRadius *
                0.62
            : rarity
                .unlockBurstRadius
    }

    var body: some View {
        ZStack {
            ForEach(
                0..<particleCount,
                id: \.self
            ) { index in
                particle(
                    index: index
                )
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            burst = false

            DispatchQueue.main
                .async {
                    burst = true
                }
        }
    }

    private func particle(
        index: Int
    ) -> some View {
        let count =
            max(
                particleCount,
                1
            )
        let angle =
            (
                Double(index) /
                Double(count)
            ) *
            Double.pi *
            2
        let wave =
            CGFloat(
                index % 5
            ) * 7
        let radius =
            burstRadius +
            (
                reduced
                    ? wave * 0.55
                    : wave
            )
        let x =
            cos(angle) *
            Double(radius)
        let y =
            sin(angle) *
            Double(radius)
        let color =
            rarity
                .particlePalette[
                    index %
                    rarity
                        .particlePalette
                        .count
                ]
        let size =
            CGFloat(
                4 +
                (index % 4) * 2
            )

        return RoundedRectangle(
            cornerRadius:
                size * 0.35,
            style: .continuous
        )
        .fill(color)
        .frame(
            width: size,
            height:
                size *
                (
                    index % 3 == 0
                        ? 2.2
                        : 1
                )
        )
        .rotationEffect(
            .degrees(
                Double(
                    index * 29
                )
            )
        )
        .offset(
            x:
                burst
                    ? CGFloat(x)
                    : 0,
            y:
                burst
                    ? CGFloat(y)
                    : 0
        )
        .scaleEffect(
            burst
                ? 0.15
                : 1
        )
        .opacity(
            burst
                ? 0
                : 1
        )
        .animation(
            .easeOut(
                duration:
                    0.62 +
                    Double(
                        index % 4
                    ) * 0.07
            )
            .delay(
                Double(
                    index % 6
                ) * 0.012
            ),
            value: burst
        )
    }
}

@MainActor
enum AchievementUnlockFeedback {
    static func play(
        rarity: TrophyRarity,
        soundEnabled: Bool,
        hapticsEnabled: Bool
    ) {
        if hapticsEnabled {
            playHaptics(
                rarity: rarity
            )
        }

        if soundEnabled {
            AchievementUnlockSoundPlayer
                .shared
                .play(
                    rarity: rarity
                )
        }
    }

    private static func playHaptics(
        rarity: TrophyRarity
    ) {
        switch rarity {
        case .core:
            UIImpactFeedbackGenerator(
                style: .light
            )
            .impactOccurred(
                intensity: 0.58
            )

        case .rare:
            UIImpactFeedbackGenerator(
                style: .medium
            )
            .impactOccurred(
                intensity: 0.72
            )

        case .epic:
            UIImpactFeedbackGenerator(
                style: .heavy
            )
            .impactOccurred(
                intensity: 0.86
            )

            DispatchQueue.main
                .asyncAfter(
                    deadline:
                        .now() + 0.11
                ) {
                    UIImpactFeedbackGenerator(
                        style: .medium
                    )
                    .impactOccurred(
                        intensity:
                            0.65
                    )
                }

        case .signature:
            UINotificationFeedbackGenerator()
                .notificationOccurred(
                    .success
                )

            DispatchQueue.main
                .asyncAfter(
                    deadline:
                        .now() + 0.14
                ) {
                    UIImpactFeedbackGenerator(
                        style: .heavy
                    )
                    .impactOccurred(
                        intensity:
                            1.0
                    )
                }
        }
    }
}

@MainActor
private final class AchievementUnlockSoundPlayer {
    static let shared =
        AchievementUnlockSoundPlayer()

    private let engine =
        AVAudioEngine()
    private let player =
        AVAudioPlayerNode()
    private let sampleRate =
        44_100.0
    private lazy var format =
        AVAudioFormat(
            standardFormatWithSampleRate:
                sampleRate,
            channels: 1
        )!

    private init() {
        engine.attach(player)
        engine.connect(
            player,
            to:
                engine
                    .mainMixerNode,
            format: format
        )
    }

    func play(
        rarity: TrophyRarity
    ) {
        let session =
            AVAudioSession
                .sharedInstance()

        try? session.setCategory(
            .ambient,
            mode: .default,
            options:
                [.mixWithOthers]
        )
        try? session.setActive(true)

        if !engine.isRunning {
            engine.prepare()
            try? engine.start()
        }

        let profile =
            soundProfile(
                for: rarity
            )
        let frameCount =
            AVAudioFrameCount(
                sampleRate *
                profile.duration
            )

        guard
            let buffer =
                AVAudioPCMBuffer(
                    pcmFormat:
                        format,
                    frameCapacity:
                        frameCount
                ),
            let samples =
                buffer
                    .floatChannelData?[
                        0
                    ]
        else {
            return
        }

        buffer.frameLength =
            frameCount

        for frame in
            0..<Int(frameCount) {
            let time =
                Double(frame) /
                sampleRate
            let fadeIn =
                min(
                    1,
                    time / 0.018
                )
            let fadeOut =
                min(
                    1,
                    max(
                        0,
                        (
                            profile
                                .duration -
                            time
                        ) /
                        0.11
                    )
                )
            let envelope =
                fadeIn *
                fadeOut

            var value = 0.0

            for (
                noteIndex,
                frequency
            ) in
                profile
                    .frequencies
                    .enumerated()
            {
                let stagger =
                    Double(noteIndex) *
                    profile
                        .stagger
                let localTime =
                    max(
                        0,
                        time - stagger
                    )

                guard time >= stagger
                else {
                    continue
                }

                let fundamental =
                    sin(
                        2 *
                        Double.pi *
                        frequency *
                        localTime
                    )
                let harmonic =
                    0.24 *
                    sin(
                        2 *
                        Double.pi *
                        frequency *
                        2 *
                        localTime
                    )

                value +=
                    fundamental +
                    harmonic
            }

            let divisor =
                Double(
                    max(
                        profile
                            .frequencies
                            .count,
                        1
                    )
                )

            samples[frame] =
                Float(
                    value /
                    divisor *
                    profile.volume *
                    envelope
                )
        }

        player.stop()
        player.scheduleBuffer(
            buffer,
            at: nil,
            options: .interrupts
        )
        player.play()
    }

    private func soundProfile(
        for rarity:
            TrophyRarity
    ) -> (
        frequencies: [Double],
        duration: Double,
        stagger: Double,
        volume: Double
    ) {
        switch rarity {
        case .core:
            return (
                [523.25],
                0.19,
                0,
                0.16
            )

        case .rare:
            return (
                [
                    523.25,
                    659.25
                ],
                0.28,
                0.045,
                0.16
            )

        case .epic:
            return (
                [
                    523.25,
                    659.25,
                    783.99
                ],
                0.40,
                0.055,
                0.17
            )

        case .signature:
            return (
                [
                    392.00,
                    523.25,
                    659.25,
                    783.99
                ],
                0.55,
                0.065,
                0.18
            )
        }
    }
}
