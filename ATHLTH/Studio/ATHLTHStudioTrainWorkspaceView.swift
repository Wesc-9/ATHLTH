import SwiftUI

/// A full-screen iPad shell around the same Train views and stores as iPhone.
/// The shell provides one reliable way back to Studio even when Train hides
/// its own navigation bar. It owns no workout or plan editing state.
struct ATHLTHStudioTrainWorkspaceView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var navigationRequest: ATHLTHTrainNavigationRequest?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Back to Studio",
                            norwegian: "Tilbake til Studio"
                        ),
                        systemImage: "chevron.left"
                    )
                    .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(ATHLTHStudioStyle.ink)

                Spacer(minLength: 12)

                Text("ATHLTH STUDIO")
                    .font(.caption.weight(.semibold))
                    .tracking(1.6)
                    .foregroundStyle(ATHLTHStudioStyle.gold)
            }
            .padding(.horizontal, 22)
            .frame(minHeight: 54)
            .background(.regularMaterial)
            .overlay(alignment: .bottom) {
                ATHLTHStudioStyle.outline.opacity(0.5)
                    .frame(height: 1)
            }

            ATHLTHTrainView(
                navigationRequest: $navigationRequest,
                isActive: true
            )
            .environment(\.athlthStudioFullscreenEditing, true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(ATHLTHStudioStyle.canvas.ignoresSafeArea())
    }
}
