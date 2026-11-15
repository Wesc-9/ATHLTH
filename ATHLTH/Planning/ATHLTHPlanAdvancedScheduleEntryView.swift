import SwiftUI

/// Real advanced setup screen. Shares the approved visual system with Simple
/// while keeping the advanced duration and week-to-week options.
struct ATHLTHPlanAdvancedScheduleEntryView: View {
    @Binding var title: String
    @Binding var startDate: Date
    @Binding var weekCount: Int
    @Binding var varyWeekdays: Bool

    let planningApproach: ATHLTHPlanWeekPlanningApproach?
    let onChooseApproach: (ATHLTHPlanWeekPlanningApproach) -> Void
    let selectedDays: Set<Int>
    let suggestedName: String
    let onToggleDay: (Int) -> Void
    let onSelectSimple: () -> Void

    var body: some View {
        ATHLTHPlanSetupFields(
            title: $title,
            startDate: $startDate,
            weekCount: $weekCount,
            selectedDays: selectedDays,
            suggestedName: suggestedName,
            advanced: true,
            planningApproach: planningApproach,
            varyWeekdays: $varyWeekdays,
            onToggleDay: onToggleDay,
            onChooseApproach: onChooseApproach,
            onModeChange: { isAdvanced in
                if !isAdvanced { onSelectSimple() }
            }
        )
    }
}
