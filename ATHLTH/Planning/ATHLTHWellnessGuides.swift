import SwiftUI

/// Offline, ATHLTH-authored gentle breathing and stretching guidance.
struct ATHLTHWellnessGuide: Identifiable, Hashable {
    enum Category: Hashable { case zen, stretching }
    let id: String
    let category: Category
    let titleNO: String
    let titleEN: String
    let detailNO: String
    let detailEN: String
    let seconds: Int
    let icon: String
    let inhale: Int
    let exhale: Int

    var title: String {
        ATHLTHLocalization.choose(english: titleEN, norwegian: titleNO)
    }
    var instructions: String {
        ATHLTHLocalization.choose(english: detailEN, norwegian: detailNO)
    }
    var durationText: String {
        "\(seconds / 60) min" + (seconds % 60 == 0 ? "" : " \(seconds % 60) sek")
    }

    static let all: [Self] = [
        .init(id: "calm-46", category: .zen,
              titleNO: "Rolig pust 4–6", titleEN: "Gentle breathing 4–6",
              detailNO: "Sitt behagelig. Pust rolig inn i fire sekunder og ut i seks. Ikke press pusten. Gå tilbake til naturlig pust ved ubehag.",
              detailEN: "Sit comfortably. Breathe in gently for four seconds and out for six. Never force it. Return to your natural breath if uncomfortable.",
              seconds: 180, icon: "wind", inhale: 4, exhale: 6),
        .init(id: "breath-break", category: .zen,
              titleNO: "To minutter pustepause", titleEN: "Two-minute breathing break",
              detailNO: "Senk skuldrene. Pust inn i fire sekunder og ut i fire, rolig og uten å holde pusten.",
              detailEN: "Relax your shoulders. Breathe in for four seconds and out for four, gently and without holding your breath.",
              seconds: 120, icon: "leaf", inhale: 4, exhale: 4),
        .init(id: "mindful-calm", category: .zen,
              titleNO: "Fem minutter ro", titleEN: "Five minutes of calm",
              detailNO: "Sitt eller ligg behagelig. Følg pusten som den er, og la tankene passere uten å presse dem bort.",
              detailEN: "Sit or lie comfortably. Notice your natural breathing and let thoughts pass without forcing them away.",
              seconds: 300, icon: "sparkles", inhale: 0, exhale: 0),
        .init(id: "neck", category: .stretching,
              titleNO: "Skånsom nakkestrekk", titleEN: "Gentle neck stretch",
              detailNO: "Sitt oppreist og len øret forsiktig mot skulderen. Ikke trekk i hodet. Bytt side halvveis.",
              detailEN: "Sit tall and gently tip an ear toward your shoulder. Never pull your head. Switch sides halfway.",
              seconds: 60, icon: "person.crop.circle", inhale: 0, exhale: 0),
        .init(id: "shoulder", category: .stretching,
              titleNO: "Bryst og skuldre", titleEN: "Chest and shoulders",
              detailNO: "Legg underarmen lett mot en dørkarm og roter kroppen forsiktig vekk. Bytt side halvveis.",
              detailEN: "Rest a forearm against a door frame and gently rotate away. Switch sides halfway.",
              seconds: 60, icon: "figure.cooldown", inhale: 0, exhale: 0),
        .init(id: "hip", category: .stretching,
              titleNO: "Hofteleddsbøyer", titleEN: "Hip flexor",
              detailNO: "Sett ett kne i gulvet og den andre foten foran. Skyv hoften rolig frem. Bytt side halvveis.",
              detailEN: "Kneel with one foot in front. Move your hips gently forward. Switch sides halfway.",
              seconds: 80, icon: "figure.flexibility", inhale: 0, exhale: 0),
        .init(id: "calves", category: .stretching,
              titleNO: "Leggstrekk", titleEN: "Calf stretch",
              detailNO: "Sett hendene mot en vegg, før ett bein bakover og hold hælen nede. Bytt side halvveis.",
              detailEN: "Face a wall, step one leg back and keep your heel on the floor. Switch sides halfway.",
              seconds: 60, icon: "figure.walk", inhale: 0, exhale: 0),
        .init(id: "back", category: .stretching,
              titleNO: "Myk ryggmobilitet", titleEN: "Gentle back mobility",
              detailNO: "Stå på alle fire. Rund ryggen og senk magen forsiktig, uten å presse ytterstillingene.",
              detailEN: "On hands and knees, gently round your back and lower your belly without forcing the movement.",
              seconds: 90, icon: "figure.pilates", inhale: 0, exhale: 0),
        .init(id: "hamstrings", category: .stretching,
              titleNO: "Bakside lår", titleEN: "Hamstring stretch",
              detailNO: "Sitt med ett bein strakt og len deg litt frem fra hoften med lang rygg. Bytt side halvveis.",
              detailEN: "Sit with one leg straight, hinge forward gently at your hips, and switch sides halfway.",
              seconds: 60, icon: "figure.cooldown", inhale: 0, exhale: 0)
    ]
}

struct ATHLTHWellnessGuideTimer: View {
    let guide: ATHLTHWellnessGuide
    @State private var remaining = 0
    @State private var running = false

    private var breathingPrompt: String {
        let total = guide.inhale + guide.exhale
        guard total > 0 else {
            return ATHLTHLocalization.choose(english: "Breathe naturally", norwegian: "Pust naturlig")
        }
        let phase = (guide.seconds - remaining) % total
        if phase < guide.inhale {
            return ATHLTHLocalization.choose(english: "Breathe in", norwegian: "Pust inn")
                + " · \(guide.inhale - phase) s"
        }
        return ATHLTHLocalization.choose(english: "Breathe out", norwegian: "Pust ut")
            + " · \(total - phase) s"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(guide.instructions)
                .font(.subheadline)
                .foregroundStyle(ATHLTHTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            ZStack {
                Circle().stroke(ATHLTHTheme.recoveryBlue.opacity(0.17), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: CGFloat(remaining) / CGFloat(max(guide.seconds, 1)))
                    .stroke(ATHLTHTheme.recoveryBlue,
                            style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 6) {
                    Text(String(format: "%02d:%02d", remaining / 60, remaining % 60))
                        .font(.system(size: 31, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(guide.category == .zen ? breathingPrompt :
                        ATHLTHLocalization.choose(english: "Time remaining", norwegian: "Tid igjen"))
                        .font(.caption.weight(.medium))
                        .multilineTextAlignment(.center)
                }
            }
            .frame(width: 178, height: 178)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("\(remaining) " + ATHLTHLocalization.choose(
                english: "seconds remaining", norwegian: "sekunder igjen"))
            HStack(spacing: 9) {
                Button {
                    if remaining == 0 { remaining = guide.seconds }
                    running.toggle()
                } label: {
                    Label(running
                          ? ATHLTHLocalization.choose(english: "Pause", norwegian: "Pause")
                          : ATHLTHLocalization.choose(english: "Start / resume", norwegian: "Start / fortsett"),
                          systemImage: running ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.recoveryBlue)
                Button {
                    running = false
                    remaining = guide.seconds
                } label: {
                    Label(ATHLTHLocalization.choose(english: "Reset", norwegian: "Nullstill"),
                          systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            Text(ATHLTHLocalization.choose(
                english: "Stop if you feel pain, dizziness or discomfort.",
                norwegian: "Stopp ved smerte, svimmelhet eller ubehag."
            ))
            .font(.caption2)
            .foregroundStyle(ATHLTHTheme.mutedText)
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 17))
        .onAppear { remaining = guide.seconds }
        .task(id: running) {
            while running && remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled && running else { return }
                remaining = max(0, remaining - 1)
            }
            if remaining == 0 { running = false }
        }
    }
}
