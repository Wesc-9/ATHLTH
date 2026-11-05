import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// A user-initiated, in-memory PDF. No HealthKit details are written to a
/// temporary app file until the system export destination is chosen.
struct ATHLTHStudioReportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let bytes = configuration.file.regularFileContents
        else { throw CocoaError(.fileReadCorruptFile) }
        data = bytes
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum ATHLTHStudioReportRenderer {
    static func make(
        workouts: [WorkoutSummary], days: Int,
        includeDetails: Bool, includeEnergy: Bool,
        now: Date = .now
    ) -> Data {
        let from = Calendar.current.date(
            byAdding: .day, value: -max(1, min(365, days)), to: now
        ) ?? .distantPast
        let rows = workouts.filter {
            $0.startDate >= from && $0.startDate <= now &&
            $0.duration.isFinite && $0.duration >= 0
        }.sorted { $0.startDate > $1.startDate }

        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let ink = UIColor(red: 0.19, green: 0.18, blue: 0.16, alpha: 1)
        let gold = UIColor(red: 0.69, green: 0.54, blue: 0.32, alpha: 1)
        let muted = UIColor(red: 0.43, green: 0.41, blue: 0.38, alpha: 1)

        let minutes = rows.reduce(0.0) { $0 + $1.duration / 60 }
        let distance = rows.reduce(0.0) {
            $0 + max(0, $1.distanceKilometers ?? 0)
        }
        let running = rows.filter { $0.activity == .running }
        let strength = rows.filter { $0.activity == .strength }
        let bestPace = running.compactMap { row -> Double? in
            guard let km = row.distanceKilometers, km >= 1,
                  row.duration > 0 else { return nil }
            let pace = row.duration / km
            return (120...3_600).contains(pace) ? pace : nil
        }.min()

        return renderer.pdfData { context in
            func put(_ value: String, _ x: CGFloat, _ y: CGFloat,
                     width: CGFloat = 500, size: CGFloat = 11,
                     color: UIColor? = nil, bold: Bool = false) {
                let foreground = color ?? ink
                let font = bold
                    ? UIFont.systemFont(ofSize: size, weight: .semibold)
                    : UIFont.systemFont(ofSize: size)
                (value as NSString).draw(
                    in: CGRect(x: x, y: y, width: width, height: size * 2.3),
                    withAttributes: [
                        .font: font,
                        .foregroundColor: foreground
                    ]
                )
            }

            func header(_ pageNumber: Int) {
                context.beginPage()
                UIColor(red: 0.984, green: 0.976, blue: 0.96, alpha: 1).setFill()
                UIRectFill(page)
                put("ATHLTH", 36, 26, size: 15, color: gold, bold: true)
                put("YOUR BODY. YOUR DATA. YOUR PROGRESS.", 132, 31,
                    width: 350, size: 9, color: muted)
                gold.setFill()
                UIRectFill(CGRect(x: 36, y: 55, width: 523, height: 2))
                put("PERSONAL TRAINING REPORT", 36, 72,
                    size: 23, bold: true)
                put("\(from.formatted(date: .abbreviated, time: .omitted)) — " +
                    now.formatted(date: .abbreviated, time: .omitted),
                    36, 110, size: 11, color: muted)
                put("Page \(pageNumber)", 492, 31, width: 70, size: 9, color: muted)
                put("Generated locally from available recorded workouts. " +
                    "Missing Health permission or data may affect coverage.",
                    36, 796, width: 525, size: 8, color: muted)
            }

            header(1)
            put("WORKOUT SUMMARY", 36, 153, size: 12, color: gold, bold: true)
            put("Recorded workouts", 36, 184, size: 11, color: muted)
            put("\(rows.count)", 195, 180, size: 16, bold: true)
            put("Training time", 36, 218, size: 11, color: muted)
            put(String(format: "%.1f h", minutes / 60), 195, 214,
                size: 16, bold: true)
            put("Distance", 36, 252, size: 11, color: muted)
            put(String(format: "%.2f km", distance), 195, 248,
                size: 16, bold: true)
            put("Running / strength", 36, 286, size: 11, color: muted)
            put("\(running.count) / \(strength.count)", 195, 282,
                size: 16, bold: true)

            put("PERIOD HIGHLIGHTS", 36, 332, size: 12, color: gold, bold: true)
            if let bestPace {
                let rounded = Int(bestPace.rounded())
                put("Best recorded run average pace in this period:",
                    36, 362, size: 10, color: muted)
                put(String(format: "%d:%02d min/km",
                           rounded / 60, rounded % 60), 36, 384,
                    size: 16, bold: true)
            } else {
                put("Insufficient running data for a valid pace comparison.",
                    36, 364, width: 500, size: 10, color: muted)
            }
            put("These are observations for the selected dates, not lifetime " +
                "personal records, clinical recovery results or injury forecasts.",
                36, 430, width: 518, size: 10, color: muted)

            guard includeDetails else {
                put("Workout-by-workout details were excluded by your selection.",
                    36, 478, width: 520, size: 10, color: muted)
                return
            }

            // Put data rows on separate pages. Never allow a page boundary to
            // cut a health entry in half. Only explicitly selected columns
            // are exported.
            let pageSize = 22
            for offset in stride(from: 0, to: rows.count, by: pageSize) {
                header(2 + offset / pageSize)
                put("RECORDED SESSIONS", 36, 153, size: 13, color: gold, bold: true)
                put("Date", 36, 189, size: 10, bold: true)
                put("Activity", 145, 189, size: 10, bold: true)
                put("Time", 302, 189, size: 10, bold: true)
                put("Distance", 375, 189, size: 10, bold: true)
                if includeEnergy {
                    put("Energy", 467, 189, size: 10, bold: true)
                }
                for (index, row) in rows.dropFirst(offset).prefix(pageSize).enumerated() {
                    let y = CGFloat(217 + index * 24)
                    if index.isMultiple(of: 2) {
                        UIColor.white.withAlphaComponent(0.65).setFill()
                        UIRectFill(CGRect(x: 34, y: y - 3, width: 526, height: 23))
                    }
                    put(row.startDate.formatted(date: .abbreviated,
                                                time: .omitted),
                        36, y, width: 105, size: 9)
                    put(row.activity.rawValue, 145, y, width: 150, size: 9)
                    put("\(Int(row.duration / 60)) min",
                        302, y, width: 70, size: 9)
                    put(row.distanceKilometers.map {
                        String(format: "%.2f km", $0)
                    } ?? "—", 375, y, width: 86, size: 9)
                    if includeEnergy {
                        put(row.activeEnergyKilocalories.map {
                            String(format: "%.0f kcal", $0)
                        } ?? "—", 467, y, width: 90, size: 9)
                    }
                }
            }
        }
    }
}

/// Health data are never included in a PDF without an explicit export action.
struct ATHLTHStudioReportExportView: View {
    @EnvironmentObject private var health: HealthKitManager
    @Environment(\.dismiss) private var dismiss
    @State private var periodDays = 90
    @State private var includeDetails = false
    @State private var includeEnergy = false
    @State private var exportedFile: ATHLTHStudioReportDocument?
    @State private var showingExporter = false
    @State private var exportError: String?

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(tr("Report period", "Rapportperiode"),
                           selection: $periodDays) {
                        Text(tr("28 days", "28 dager")).tag(28)
                        Text(tr("90 days", "90 dager")).tag(90)
                        Text(tr("1 year", "1 år")).tag(365)
                    }
                    Toggle(tr("Include individual workouts",
                              "Inkluder enkeltøkter"), isOn: $includeDetails)
                    Toggle(tr("Include active energy", "Inkluder aktiv energi"),
                           isOn: $includeEnergy)
                        .disabled(!includeDetails)
                } header: {
                    Text(tr("Choose what to share", "Velg hva du vil dele"))
                }
                Section {
                    Text(tr(
                        "The report is prepared on your device after you press Export. It contains only the selected training data. It is not uploaded by ATHLTH Studio.",
                        "Rapporten opprettes på enheten når du trykker Eksporter. Den inneholder bare de valgte treningsdataene og lastes ikke opp av ATHLTH Studio."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    Text(tr(
                        "A missing workout might mean HealthKit access was not granted; an empty report is not proof of zero training.",
                        "Manglende økter kan skyldes HealthKit-tilgang. En tom rapport betyr ikke nødvendigvis at du ikke har trent."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Section {
                    Button {
                        let data = ATHLTHStudioReportRenderer.make(
                            workouts: health.workouts, days: periodDays,
                            includeDetails: includeDetails,
                            includeEnergy: includeEnergy
                        )
                        exportedFile = ATHLTHStudioReportDocument(data: data)
                        showingExporter = true
                    } label: {
                        Label(tr("Export training report as PDF",
                                 "Eksporter treningsrapport som PDF"),
                              systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("athlth-ipad-report-export")
                }
            }
            .navigationTitle(tr("Training report", "Treningsrapport"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done", "Ferdig")) { dismiss() }
                }
            }
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportedFile,
            contentType: .pdf,
            defaultFilename: "ATHLTH_Training_Report"
        ) { result in
            if case let .failure(error) = result {
                exportError = error.localizedDescription
            }
            exportedFile = nil
        }
        .alert(
            tr("Could not export report", "Kunne ikke eksportere rapporten"),
            isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }
}
