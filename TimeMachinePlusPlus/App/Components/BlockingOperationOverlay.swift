import SwiftUI

struct BlockingOperationOverlay: View {
    var title: String
    var detail: String?
    var progress: Double?
    var canCancel: Bool
    var onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                if let progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(width: 250)
                } else {
                    ProgressView()
                        .controlSize(.regular)
                }
                Text(title)
                    .font(.headline)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if canCancel {
                    Button("Cancel", role: .cancel, action: onCancel)
                        .padding(.top, 4)
                } else {
                    Text("This window will unlock when the operation finishes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(24)
            .frame(width: 340)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 18)
        }
    }
}
