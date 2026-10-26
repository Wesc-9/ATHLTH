import SwiftUI
import Charts

/// A self-contained chart for measured Apple Health running pace.
/// Each sample keeps its HealthKit workout identity, not a potentially
/// duplicate timestamp, while the parent owns period and data selection.
struct ATHLTHTrainProgressPaceChartView: View {
    struct Sample: Identifiable, Equatable {
        let id: UUID
        let date: Date
        let minutesPerKilometer: Double
    }

    let samples: [Sample]

    var body: some View {
        Chart(samples) { sample in
            LineMark(
                x: .value("Dato", sample.date),
                y: .value("min/km", sample.minutesPerKilometer)
            )
            .interpolationMethod(.linear)
            .foregroundStyle(ATHLTHTrainDesign.bronze)
            .lineStyle(StrokeStyle(lineWidth: 2.3, lineCap: .round))

            PointMark(
                x: .value("Dato", sample.date),
                y: .value("min/km", sample.minutesPerKilometer)
            )
            .foregroundStyle(ATHLTHTrainDesign.bronze)
            .symbolSize(20)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) {
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .chartYAxis { AxisMarks(position: .leading) }
        .frame(height: 181)
        .accessibilityLabel(ATHLTHLocalization.choose(
            english: "Average running pace over time",
            norwegian: "Utvikling i gjennomsnittlig løpstempo"
        ))
    }
}
