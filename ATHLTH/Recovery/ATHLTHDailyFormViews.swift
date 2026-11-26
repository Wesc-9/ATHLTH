import Foundation
import SwiftUI

/// One optional self-report per finished workout. Private, account-scoped,
/// and independent of the recorded workout/HealthKit result.
struct ATHLTHPostWorkoutFeedback: Codable, Hashable, Identifiable {
    let workoutID: UUID
    let finishedAt: Date
    var feeling: Int?
    var exertion: Int?
    var id: UUID { workoutID }
}

enum ATHLTHPostWorkoutFeedbackStore {
    private static func key(_ account: UUID) -> String {
        "recovery.workoutFeedback." + account.uuidString
    }

    static func entries(account: UUID, defaults: UserDefaults = .standard,
                        now: Date = Date()) -> [ATHLTHPostWorkoutFeedback] {
        guard let data = defaults.data(forKey: key(account)),
              let values = try? JSONDecoder().decode([ATHLTHPostWorkoutFeedback].self, from: data)
        else { return [] }
        let cutoff = now.addingTimeInterval(-90 * 86_400)
        return Array(values.filter { $0.finishedAt >= cutoff && $0.finishedAt <= now }
            .sorted { $0.finishedAt > $1.finishedAt }.prefix(300))
    }

    @discardableResult static func save(_ item: ATHLTHPostWorkoutFeedback, account: UUID,
                                        defaults: UserDefaults = .standard, now: Date = Date()) -> Bool {
        guard item.finishedAt <= now, item.finishedAt >= now.addingTimeInterval(-90 * 86_400),
              item.feeling != nil || item.exertion != nil,
              item.feeling.map({ (1...5).contains($0) }) ?? true,
              item.exertion.map({ (1...10).contains($0) }) ?? true else { return false }
        var stored = entries(account: account, defaults: defaults, now: now)
        if let existing = stored.firstIndex(where: { $0.workoutID == item.workoutID }) {
            var updated = stored[existing]
            if let feeling = item.feeling { updated.feeling = feeling }
            if let exertion = item.exertion { updated.exertion = exertion }
            stored[existing] = updated
        } else {
            stored.insert(item, at: 0)
        }
        guard let data = try? JSONEncoder().encode(Array(stored.sorted {
            $0.finishedAt > $1.finishedAt
        }.prefix(300))) else { return false }
        defaults.set(data, forKey: key(account))
        NotificationCenter.default.post(name: Notification.Name("athlth.workoutFeedbackDidUpdate"), object: nil)
        return true
    }
}

struct ATHLTHQuickDailyFormAdvice: View {
    @EnvironmentObject private var session: AppSessionStore
    @State private var assessment: ATHLTHDailyFormPolicy.Assessment?
    private func reload() {
        assessment = session.signedIn
            ? ATHLTHDailyFormPolicy.assess(entry: RecoverySorenessStore(accountID: session.profile.userID).todayEntry, measuredScore: nil)
            : nil
    }
    var body: some View {
        Group {
            if let assessment, assessment.recommendation == .rest || assessment.recommendation == .lighter {
                VStack(alignment: .leading, spacing: 6) {
                    Label(assessment.recommendation.title, systemImage: assessment.illnessReported ? "bed.double" : "leaf")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    Text(assessment.explanation)
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    Text(ATHLTHLocalization.choose(english: "You choose whether to start or change the workout.", norwegian: "Du velger selv om du vil starte eller tilpasse økten."))
                        .font(.caption2)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(13)
                .athlthTrainPaper()
            }
        }
        .task(id: session.profile.userID) { reload() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("athlth.dailyCheckInDidUpdate"))) { _ in reload() }
    }
}

struct ATHLTHPostWorkoutFeedbackCard: View {
    @EnvironmentObject private var session: AppSessionStore
    let workoutID: UUID
    let finishedAt: Date
    @State private var feeling: Int?
    @State private var exertion: Int?
    @State private var saved = false
    @State private var owner: UUID?

    private func reload() {
        owner = session.signedIn ? session.profile.userID : nil
        let stored = owner.flatMap { id in
            ATHLTHPostWorkoutFeedbackStore.entries(account: id).first { $0.workoutID == workoutID }
        }
        feeling = stored?.feeling
        exertion = stored?.exertion
        saved = stored != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ATHLTHLocalization.choose(english: "How did the workout feel?", norwegian: "Hvordan føltes økten?"))
                .font(.headline)
            Text(ATHLTHLocalization.choose(english: "Optional · private · does not change the workout result.", norwegian: "Valgfritt · privat · endrer ikke treningsresultatet."))
                .font(.caption)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { value in
                    Button {
                        feeling = feeling == value ? nil : value
                        saved = false
                    } label: {
                        Text(["😣", "🙁", "😐", "🙂", "😊"][value - 1])
                            .font(.title2)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(feeling == value ? ATHLTHPlanDesign.accentInk.opacity(0.15) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(ATHLTHLocalization.choose(english: "Feeling \(value) of 5", norwegian: "Opplevelse \(value) av 5"))
                    .accessibilityAddTraits(feeling == value ? .isSelected : [])
                }
            }
            HStack {
                Text(ATHLTHLocalization.choose(english: "Perceived exertion", norwegian: "Opplevd intensitet"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Menu {
                    ForEach(1...10, id: \.self) { value in
                        Button("\(value)/10") { exertion = value; saved = false }
                    }
                } label: {
                    Text(exertion.map { "\($0)/10" } ?? ATHLTHLocalization.choose(english: "Choose", norwegian: "Velg"))
                }
                .tint(ATHLTHPlanDesign.accentInk)
            }
            Button {
                guard let owner, session.signedIn, owner == session.profile.userID else { return }
                saved = ATHLTHPostWorkoutFeedbackStore.save(.init(workoutID: workoutID, finishedAt: finishedAt,
                    feeling: feeling, exertion: exertion), account: owner)
            } label: {
                Label(saved ? ATHLTHLocalization.choose(english: "Saved", norwegian: "Lagret") : ATHLTHLocalization.choose(english: "Save feedback", norwegian: "Lagre vurdering"),
                      systemImage: saved ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(ATHLTHPlanDesign.accentInk)
            .disabled(saved || (feeling == nil && exertion == nil) || owner == nil)
        }
        .padding(12)
        .task(id: "\(session.profile.userID)-\(workoutID)") { reload() }
    }
}
