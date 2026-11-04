import SwiftUI

/// Studio styling intentionally stays independent of the existing iPhone cards.
enum ATHLTHStudioStyle {
    static let canvas = Color(red: 0.985, green: 0.979, blue: 0.965)
    static let paper = Color.white
    static let ink = Color(red: 0.19, green: 0.18, blue: 0.16)
    static let gold = Color(red: 0.69, green: 0.54, blue: 0.32)
    static let outline = Color(red: 0.88, green: 0.85, blue: 0.80)
}

struct ATHLTHStudioMetricCard: View {
    let title: String
    let value: String
    let note: String
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 27, weight: .semibold, design: .rounded))
                .foregroundStyle(ATHLTHStudioStyle.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(note)
                .font(.caption2)
                .foregroundStyle(ATHLTHStudioStyle.gold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(ATHLTHStudioStyle.paper, in: RoundedRectangle(cornerRadius: 19))
        .overlay(RoundedRectangle(cornerRadius: 19).stroke(ATHLTHStudioStyle.outline.opacity(0.45)))
    }
}
