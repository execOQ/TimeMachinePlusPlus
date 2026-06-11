//
//  RegexIntelligencePopover.swift
//  TimeMachinePlusPlus
//
//  Created by Artem Bagin on 19.05.2026.
//

import SwiftUI

@MainActor
@Observable
final class AIRegexGenerationState {
    var isGenerating = false
    var errorMessage: String?
    private var task: Task<Void, Never>?

    func generate(
        request: String,
        onSuccess: @escaping (String) -> Void
    ) {
        task?.cancel()
        errorMessage = nil
        isGenerating = true

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await AppleIntelligenceRegexHelper.generateRegex(for: request)
                guard !Task.isCancelled else { return }
                onSuccess(result)
                self.isGenerating = false
            } catch {
                guard !Task.isCancelled else { return }
                self.errorMessage = error.localizedDescription
                self.isGenerating = false
            }
        }
    }
}

struct RegexIntelligencePopover: View {
    @Binding var request: String
    @Binding var generatedPattern: String
    @Binding var generatedForRequest: String
    var generationState: AIRegexGenerationState
    let onUse: (String) -> Void
    @Environment(AppStateStore.self) private var store

    private var trimmedRequest: String {
        request.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isRequestLongEnough: Bool {
        trimmedRequest.count >= 8
    }

    private var isAlreadyGenerated: Bool {
        !generationState.isGenerating &&
        !generatedPattern.isEmpty &&
        !generatedForRequest.isEmpty &&
        trimmedRequest == generatedForRequest
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Regex Helper")
                    .font(.headline)
                Spacer()
            }

            TextField("e.g. All .log files in any folder", text: $request, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2 ... 4)
                .disabled(generationState.isGenerating)
                .onSubmit { primaryAction() }

            requestHint()
            generatedPatternView()
            generationErrorView()
            footerControls()
        }
        .padding(12)
        .frame(width: 340)
        .onKeyPress(.return) {
            primaryAction()
            return .handled
        }
        .onDisappear(perform: onDisappear)
    }

    // MARK: - View Components

    @ViewBuilder
    private func requestHint() -> some View {
        if !trimmedRequest.isEmpty && !isRequestLongEnough {
            Text("Add more detail to get a useful pattern.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func generatedPatternView() -> some View {
        if !generatedPattern.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text("Generated")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(generatedPattern)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    @ViewBuilder
    private func generationErrorView() -> some View {
        if let errorMessage = generationState.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func footerControls() -> some View {
        HStack {
            if generationState.isGenerating {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()

            Button("Generate") {
                generatePattern()
            }
            .disabled(generationState.isGenerating || !isRequestLongEnough || isAlreadyGenerated)

            Button("Use") {
                onUse(generatedPattern)
            }
            .buttonStyle(.borderedProminent)
            .disabled(generatedPattern.isEmpty || generationState.isGenerating)
        }
    }
}

private extension RegexIntelligencePopover {
    func primaryAction() {
        if isAlreadyGenerated {
            onUse(generatedPattern)
        } else if isRequestLongEnough && !generationState.isGenerating {
            generatePattern()
        }
    }

    func generatePattern() {
        let patternBinding = _generatedPattern
        let forRequestBinding = _generatedForRequest
        let requestText = trimmedRequest
        generationState.generate(request: requestText) { result in
            patternBinding.wrappedValue = result
            forRequestBinding.wrappedValue = requestText
        }
    }

    func onDisappear() {
        store.save()
    }
}
