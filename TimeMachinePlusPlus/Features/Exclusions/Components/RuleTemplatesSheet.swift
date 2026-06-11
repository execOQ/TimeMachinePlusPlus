//
//  RuleTemplatesSheet.swift
//  TimeMachinePlusPlus
//
//  Created by Artem Bagin on 19.05.2026.
//

import SwiftUI

struct RuleTemplatesSheet: View {
    @Environment(AppStateStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager

    private var categories: [String] {
        var seen: Set<String> = []
        return RuleTemplate.common.compactMap { template in
            guard !seen.contains(template.category) else { return nil }
            seen.insert(template.category)
            return template.category
        }
    }

    private var missingTemplateCount: Int {
        RuleTemplate.common.filter { !store.hasRule(from: $0) }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            header()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(categories, id: \.self) { category in
                        templateSection(category)
                    }
                }
                .padding()
            }

            Divider()

            footer()
        }
        .frame(maxWidth: 640, maxHeight: 620)
        .navigationTitle("Rule Templates")
        .navigationSubtitle("Add common development artifacts to your exclusion rules.")
    }

    // MARK: - View Components

    private func header() -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Rule Templates")
                    .font(.title3.weight(.semibold))
                Text("Add common development artifacts to your exclusion rules.")
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
    }

    private func footer() -> some View {
        HStack {
            Text("\(missingTemplateCount) templates available")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Done") {
                dismiss()
            }

            Button {
                store.addMissingRules(from: RuleTemplate.common, undoManager: undoManager)
            } label: {
                Label("Add All Missing", systemImage: "plus.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(missingTemplateCount == 0)
        }
        .padding()
    }

    private func templateSection(_ category: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AppSectionLabel(title: category, topPadding: 0)

            VStack(spacing: 0) {
                let templates = RuleTemplate.common.filter { $0.category == category }
                ForEach(templates) { template in
                    RuleTemplateRow(template: template)

                    if template.id != templates.last?.id {
                        Divider()
                            .padding(.leading, 36)
                    }
                }
            }
            .boxContainer(padding: 0)
        }
    }
}

private struct RuleTemplateRow: View {
    @Environment(AppStateStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    var template: RuleTemplate

    private var isAdded: Bool {
        store.hasRule(from: template)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 5) {
                Text(template.name)
                    .font(.headline)

                Text(template.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(template.pattern.replacingOccurrences(of: "\n", with: ", "))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            Button {
                store.addRule(from: template, undoManager: undoManager)
            } label: {
                Label(isAdded ? "Added" : "Add", systemImage: isAdded ? "checkmark" : "plus")
            }
            .disabled(isAdded)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }

    private var iconName: String {
        switch template.category {
        case "Node": return "hexagon"
        case "Python": return "chevron.left.forwardslash.chevron.right"
        case "Ruby": return "diamond"
        case "Xcode", "Swift": return "hammer"
        case "Java": return "cup.and.saucer"
        case "Rust", "Go": return "shippingbox"
        default: return "folder.badge.gearshape"
        }
    }
}
