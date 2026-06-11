import SwiftUI

struct HeaderView<Actions: View>: View {
    var title: LocalizedStringKey
    var subtitle: LocalizedStringKey
    var additionalSubtitle: LocalizedStringKey? = nil
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.weight(.semibold))

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .overlay(alignment: .topTrailing) {
                        if let additionalSubtitle {
                            InfoPopView(additionalSubtitle)
                        }
                    }
            }

            Spacer()

            HStack(spacing: 8) {
                actions()
            }
        }
        .padding(20)
        .background(.ultraThinMaterial)
    }
}
