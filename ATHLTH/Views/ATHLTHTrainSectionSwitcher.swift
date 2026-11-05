import SwiftUI

struct ATHLTHTrainSectionSwitcher: View {
    let titles: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(
                Array(titles.enumerated()),
                id: \.offset
            ) { index, title in
                Button {
                    guard selection != index
                    else {
                        return
                    }

                    withAnimation(
                        .easeOut(duration: 0.16)
                    ) {
                        selection = index
                    }
                } label: {
                    Text(title)
                        .font(
                            .system(
                                size: 12.5,
                                weight:
                                    selection == index
                                        ? .bold
                                        : .semibold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(
                            selection == index
                                ? ATHLTHTheme.primaryText
                                : Color.white.opacity(0.92)
                        )
                        .padding(.horizontal, 15)
                        .frame(height: 34)
                        .background {
                            ZStack {
                                Capsule()
                                    .fill(.ultraThinMaterial)

                                Capsule()
                                    .fill(
                                        selection == index
                                            ? Color.white.opacity(0.94)
                                            : Color.black.opacity(0.24)
                                    )
                            }
                        }
                        .overlay {
                            Capsule()
                                .stroke(
                                    Color.white.opacity(
                                        selection == index
                                            ? 0.54
                                            : 0.28
                                    ),
                                    lineWidth: 0.8
                                )
                        }
                        .shadow(
                            color:
                                Color.black.opacity(
                                    selection == index
                                        ? 0.11
                                        : 0.07
                                ),
                            radius: 8,
                            y: 3
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(
                    selection == index
                        ? .isSelected
                        : []
                )
            }
        }
    }
}
