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

    /// Stable muscle-group keys used by the offline recovery library.
    /// Existing guide IDs and workout blocks remain unchanged.
    var focusKey: String {
        switch id {
        case "neck", "shoulder", "triceps", "rear-shoulder",
             "wrist-flexor", "wrist-extensor", "side-bend":
            return "upper"
        case "back", "lats", "child-pose", "thoracic-rotation",
             "seated-spinal-twist", "knees-to-chest":
            return "back"
        case "hip", "figure-four", "butterfly", "hip-90-90":
            return "hips"
        case "calves", "hamstrings", "quadriceps", "soleus", "ankle-rock":
            return "legs"
        default:
            return category == .zen ? "calm" : "all"
        }
    }

    var focusTitle: String {
        switch focusKey {
        case "upper": return ATHLTHLocalization.choose(
            english: "Upper body", norwegian: "Overkropp")
        case "back": return ATHLTHLocalization.choose(
            english: "Back & spine", norwegian: "Rygg")
        case "hips": return ATHLTHLocalization.choose(
            english: "Hips & glutes", norwegian: "Hofte og sete")
        case "legs": return ATHLTHLocalization.choose(
            english: "Legs & ankles", norwegian: "Bein og ankler")
        case "calm": return ATHLTHLocalization.choose(
            english: "Breathing & calm", norwegian: "Pust og ro")
        default: return ATHLTHLocalization.choose(
            english: "Mobility", norwegian: "Mobilitet")
        }
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
        .init(id: "triceps", category: .stretching,
              titleNO: "Tricepsstrekk over hodet", titleEN: "Overhead triceps stretch",
              detailNO: "Bøy én arm bak hodet og støtt albuen lett med den andre hånden. Hold skuldrene lave, og bytt side halvveis.",
              detailEN: "Bend one arm behind your head and gently support the elbow. Keep shoulders relaxed and switch sides halfway.",
              seconds: 60, icon: "figure.flexibility", inhale: 0, exhale: 0),
        .init(id: "rear-shoulder", category: .stretching,
              titleNO: "Bakside skulder", titleEN: "Cross-body shoulder stretch",
              detailNO: "Før armen mykt på tvers av brystet og støtt overarmen med motsatt hånd. Ikke press i skulderleddet. Bytt side.",
              detailEN: "Move one arm gently across the chest, supporting the upper arm with the other hand. Avoid forcing the joint. Switch sides.",
              seconds: 60, icon: "figure.cooldown", inhale: 0, exhale: 0),
        .init(id: "wrist-flexor", category: .stretching,
              titleNO: "Underarm og håndledd", titleEN: "Wrist flexor stretch",
              detailNO: "Strekk én arm frem med håndflaten opp. Før fingrene forsiktig ned og bakover med den andre hånden. Bytt side.",
              detailEN: "Extend one arm with your palm up. Gently ease the fingers downward and backward with the other hand. Switch sides.",
              seconds: 60, icon: "hand.raised", inhale: 0, exhale: 0),
        .init(id: "wrist-extensor", category: .stretching,
              titleNO: "Overside underarm", titleEN: "Wrist extensor stretch",
              detailNO: "Strekk en arm frem med håndflaten ned. Bøy håndleddet rolig nedover og støtt med motsatt hånd. Bytt side.",
              detailEN: "Extend one arm palm down. Gently bend the wrist downward, supporting with the other hand. Switch sides.",
              seconds: 60, icon: "hand.raised", inhale: 0, exhale: 0),
        .init(id: "lats", category: .stretching,
              titleNO: "Bred ryggmuskel", titleEN: "Lat stretch",
              detailNO: "Hold hendene mot en benk eller vegg og før hoftene rolig bakover mens overkroppen senkes. Behold en behagelig ryggstilling.",
              detailEN: "Rest your hands on a bench or wall, then move your hips back while gently lowering your chest. Keep the back comfortable.",
              seconds: 60, icon: "figure.flexibility", inhale: 0, exhale: 0),
        .init(id: "child-pose", category: .stretching,
              titleNO: "Barnets posisjon", titleEN: "Child's pose",
              detailNO: "Start på alle fire, før hoftene rolig bakover mot hælene og strekk armene frem. Stopp hvis knærne er ukomfortable.",
              detailEN: "From hands and knees, ease hips toward the heels and reach arms forward. Stop if your knees feel uncomfortable.",
              seconds: 75, icon: "figure.yoga", inhale: 0, exhale: 0),
        .init(id: "thoracic-rotation", category: .stretching,
              titleNO: "Rotasjon i brystryggen", titleEN: "Thoracic spine rotation",
              detailNO: "Stå på alle fire, legg en hånd bak hodet og roter albuen rolig opp mot taket. Beveg deg kontrollert og bytt side.",
              detailEN: "On hands and knees, place one hand behind your head and gently turn the elbow toward the ceiling. Switch sides.",
              seconds: 80, icon: "figure.pilates", inhale: 0, exhale: 0),
        .init(id: "quadriceps", category: .stretching,
              titleNO: "Forside lår", titleEN: "Standing quad stretch",
              detailNO: "Stå stødig med støtte ved behov, ta tak i ankelen og før hælen rolig mot setet. Hold knærne nær hverandre. Bytt side.",
              detailEN: "Stand with support if needed, hold your ankle and gently bring the heel toward the glutes. Keep knees close. Switch sides.",
              seconds: 70, icon: "figure.stand", inhale: 0, exhale: 0),
        .init(id: "figure-four", category: .stretching,
              titleNO: "Sete og utside hofte", titleEN: "Figure-four glute stretch",
              detailNO: "Ligg på ryggen, legg den ene ankelen over motsatt kne og trekk låret rolig mot deg. Bytt side halvveis.",
              detailEN: "Lie on your back, place one ankle over the opposite knee and gently draw the thigh toward you. Switch sides halfway.",
              seconds: 80, icon: "figure.flexibility", inhale: 0, exhale: 0),
        .init(id: "butterfly", category: .stretching,
              titleNO: "Sommerfuglstrekk", titleEN: "Butterfly groin stretch",
              detailNO: "Sitt med fotsålene mot hverandre og la knærne falle rolig ut til sidene. Sitt høyt og ikke press knærne ned.",
              detailEN: "Sit with the soles of your feet together and allow your knees to relax outward. Sit tall; do not press the knees down.",
              seconds: 70, icon: "figure.yoga", inhale: 0, exhale: 0),
        .init(id: "soleus", category: .stretching,
              titleNO: "Dyp leggstrekk", titleEN: "Bent-knee calf stretch",
              detailNO: "Stå vendt mot en vegg med én fot bak. Bøy bakre kne forsiktig mens hælen holdes i gulvet. Bytt side.",
              detailEN: "Face a wall with one foot behind. Gently bend the back knee while keeping its heel grounded. Switch sides.",
              seconds: 60, icon: "figure.walk", inhale: 0, exhale: 0),
        .init(id: "ankle-rock", category: .stretching,
              titleNO: "Ankelmobilitet mot vegg", titleEN: "Knee-to-wall ankle mobility",
              detailNO: "Stå med én fot nær veggen. Før kneet rolig frem mot veggen uten å løfte hælen. Gjenta kontrollert og bytt fot.",
              detailEN: "Stand with one foot near a wall. Gently move your knee toward the wall without lifting the heel. Repeat and switch feet.",
              seconds: 75, icon: "figure.walk", inhale: 0, exhale: 0),
        .init(id: "hip-90-90", category: .stretching,
              titleNO: "90/90 hofterotasjon", titleEN: "90/90 hip switches",
              detailNO: "Sitt med bøyde knær og roter beina rolig fra side til side. Bruk hendene som støtte og beveg deg innenfor behagelig utslag.",
              detailEN: "Sit with bent knees and rotate your legs gently side to side. Use your hands for support and stay within a comfortable range.",
              seconds: 90, icon: "figure.pilates", inhale: 0, exhale: 0),
        .init(id: "seated-spinal-twist", category: .stretching,
              titleNO: "Sittende ryggrotasjon", titleEN: "Seated spinal twist",
              detailNO: "Sitt oppreist og drei overkroppen forsiktig mot den ene siden uten å presse i korsryggen. Bytt side halvveis.",
              detailEN: "Sit tall and gently turn your torso to one side without forcing your lower back. Switch sides halfway.",
              seconds: 70, icon: "figure.cooldown", inhale: 0, exhale: 0),
        .init(id: "side-bend", category: .stretching,
              titleNO: "Sidestrekk for overkroppen", titleEN: "Standing side bend",
              detailNO: "Stå med hoftebreddes avstand, løft én arm og bøy deg mykt til motsatt side. Unngå å vri kroppen. Bytt side.",
              detailEN: "Stand hip-width apart, raise one arm and gently bend to the other side. Avoid twisting the torso. Switch sides.",
              seconds: 60, icon: "figure.flexibility", inhale: 0, exhale: 0),
        .init(id: "knees-to-chest", category: .stretching,
              titleNO: "Kne mot bryst", titleEN: "Knee-to-chest stretch",
              detailNO: "Ligg på ryggen og trekk ett kne mykt mot brystet mens det andre beinet hviler. Bytt side uten å presse hoften.",
              detailEN: "Lie on your back and gently draw one knee toward your chest while the other leg rests. Switch sides without forcing the hip.",
              seconds: 60, icon: "figure.yoga", inhale: 0, exhale: 0),
        .init(id: "hamstrings", category: .stretching,
              titleNO: "Bakside lår", titleEN: "Hamstring stretch",
              detailNO: "Sitt med ett bein strakt og len deg litt frem fra hoften med lang rygg. Bytt side halvveis.",
              detailEN: "Sit with one leg straight, hinge forward gently at your hips, and switch sides halfway.",
              seconds: 60, icon: "figure.cooldown", inhale: 0, exhale: 0)
    ]
}


/// Shared block construction for the plan's stretching picker and the
/// advanced Workout Studio. A stretch is timed mobility, never a strength set.
enum ATHLTHWellnessBlockFactory {
    static func block(
        for guide: ATHLTHWellnessGuide,
        phase: WorkoutPhaseKind
    ) -> WorkoutTemplateBlock {
        var block = WorkoutTemplateBlock(
            sequence: 1, kind: .note, title: guide.title,
            exerciseSlug: nil, distanceMeters: nil,
            repetitions: nil, durationSeconds: Double(guide.seconds),
            targetWeightKilograms: nil, loadNote: nil,
            notes: guide.instructions,
            phase: guide.category == .zen ? .recovery : phase
        )
        block.wellnessKind = guide.category == .zen ? .meditation : .stretching
        return block
    }

    static var stretching: [ATHLTHWellnessGuide] {
        ATHLTHWellnessGuide.all.filter { $0.category == .stretching }
    }
}

struct ATHLTHWellnessGuideTimer: View {
    let guide: ATHLTHWellnessGuide
    var autoStart = false
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
        .onAppear {
            remaining = guide.seconds
            running = autoStart
        }
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
