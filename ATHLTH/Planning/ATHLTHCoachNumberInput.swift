import SwiftUI

/// A single directly editable value plus 44-point increment/decrement
/// controls. The binding stays nil until the athlete actually makes a choice.
struct ATHLTHCoachNumberInput: View {
    let label: String
    let unit: String
    @Binding var value: Int?
    let range: ClosedRange<Int>
    let step: Int

    @State private var editingText = ""
    @FocusState private var editing: Bool

    private var inputText: Binding<String> {
        Binding(
            get: { editingText },
            set: { text in
                let digits = String(text.filter(\.isNumber).prefix(4))
                editingText = digits
                if let number = Int(digits), range.contains(number) {
                    value = number
                } else {
                    value = nil
                }
            }
        )
    }

    private func refreshTextFromValue() {
        editingText = value.map(String.init) ?? ""
    }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                value = max(
                    range.lowerBound,
                    (value ?? range.lowerBound + step) - step
                )
            } label: {
                Image(systemName: "minus")
                    .frame(width: 44, height: 46)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(ATHLTHLocalization.choose(
                english: "Decrease \(label)", norwegian: "Reduser \(label)"
            ))
            .disabled(value == nil || value == range.lowerBound)

            Rectangle()
                .fill(ATHLTHPlanDesign.outline)
                .frame(width: 0.5, height: 24)

            HStack(spacing: 4) {
                TextField(
                    ATHLTHLocalization.choose(english: "Choose", norwegian: "Velg"),
                    text: inputText
                )
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(minWidth: 22, maxWidth: 58)
                .accessibilityLabel(label)
                .focused($editing)
                .onSubmit { editing = false }
                Text(unit)
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 46)

            Rectangle()
                .fill(ATHLTHPlanDesign.outline)
                .frame(width: 0.5, height: 24)

            Button {
                value = min(
                    range.upperBound,
                    (value ?? range.lowerBound - step) + step
                )
            } label: {
                Image(systemName: "plus")
                    .frame(width: 44, height: 46)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(ATHLTHLocalization.choose(
                english: "Increase \(label)", norwegian: "Øk \(label)"
            ))
            .disabled(value == range.upperBound)
        }
        .foregroundStyle(ATHLTHTrainDesign.bronze)
        .background(
            ATHLTHTrainDesign.canvas,
            in: RoundedRectangle(cornerRadius: 16)
        )
        .frame(maxWidth: 245)
        .onAppear(perform: refreshTextFromValue)
        .onChange(of: editing) { _, focused in
            if !focused { refreshTextFromValue() }
        }
        .onChange(of: value) { _, _ in
            if !editing { refreshTextFromValue() }
        }
    }
}
