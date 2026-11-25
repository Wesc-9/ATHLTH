import SwiftUI

/// Competition form is the first choice; sports are configured in the rules.
struct ATHLTHCompetitionEntryView: View {
    var preselectedFriend: SocialProfileCard? = nil
    var initialFormat: ATHLTHCompetitionFormat? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFormat: ATHLTHCompetitionFormat?
    @State private var initialized = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    ATHLTHTrainPageTitle(title: "Konkurranse")
                    Text("Velg hvordan dere vil konkurrere.")
                        .font(ATHLTHTrainDesign.pageSubtitle)
                        .foregroundStyle(ATHLTHTrainDesign.secondary)
                    ForEach(ATHLTHCompetitionFormat.allCases) { format in
                        Button { selectedFormat = format } label: {
                            HStack(spacing: 15) {
                                Image(systemName: format.symbol)
                                    .font(.system(size: 29, weight: .light))
                                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                                    .frame(width: 61, height: 61)
                                    .background(ATHLTHTrainDesign.paleGold.opacity(0.55),
                                        in: RoundedRectangle(cornerRadius: 18))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(format.title).font(ATHLTHTrainDesign.cardTitle)
                                        .foregroundStyle(ATHLTHTrainDesign.ink)
                                    Text(format.subtitle).font(.subheadline)
                                        .foregroundStyle(ATHLTHTrainDesign.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(format == .duel ? "2 deltakere" :
                                        "Minst \(ATHLTHCompetitionCreationPolicy.minOpponents(format) + 1) deltakere")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                                }
                                Spacer(minLength: 3)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                            }
                            .padding(16).frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
                            .athlthTrainEditorialCard()
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("athlth-competition-entry-\(format.rawValue)")
                    }
                }
                .padding(18).frame(maxWidth: 650)
                .frame(maxWidth: .infinity)
            }
            .background(ATHLTHTrainDesign.canvas.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
            }
        }
        .sheet(item: $selectedFormat) { format in
            AnyView(ATHLTHCompetitionCreationView(
                initialActivity: .running, advanced: true,
                initialFormat: format, preselectedFriend: preselectedFriend,
                choosesActivityInRules: true
            ))
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            guard !initialized else { return }
            initialized = true
            selectedFormat = initialFormat
        }
    }
}
