import SwiftUI

struct AppActionLabel: View {
    var title: String
    var systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .foregroundStyle(.primary)
    }
}

struct AppSectionHeader: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
    }
}

struct AppSectionLabel: View {
    var title: String
    var topPadding: CGFloat = 4

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .tracking(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, topPadding)
    }
}

struct AppSectionView<Content: View>: View {
    var title: String
    var description: String = ""
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AppSectionLabel(title: title, topPadding: 0)
                .padding(.leading, 8)

            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            .boxContainer(padding: 8)

            if !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
            }
        }
    }
}

struct AppPathText: View {
    var path: String
    var style: Font.TextStyle = .body
    var isSelectable = false

    @ViewBuilder
    var body: some View {
        if isSelectable {
            pathText
                .textSelection(.enabled)
        } else {
            pathText
        }
    }

    private var pathText: some View {
        Text(path)
            .font(.system(style, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.middle)
    }
}

struct AppPathRow<Trailing: View>: View {
    var path: String
    var systemImage: String = "folder"
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            AppPathText(path: path)

            Spacer()

            trailing()
        }
    }
}

struct AppPathEditor: View {
    var title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 90)
                .scrollContentBackground(.hidden)
                .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

extension View {
    func boxContainer(color: Color = .secondary, cornerRadius: CGFloat = 6, padding: CGFloat = 6) -> some View {
        self.padding(.horizontal, padding + 2)
            .padding(.vertical, padding)
            .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(color.opacity(0.15))
            )
    }
}
