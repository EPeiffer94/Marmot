import SwiftUI

/// Transient bottom toast after a real (non-dry-run) clean.
struct FreedToast: Identifiable {
    let id = UUID()
    var freed: Int64 = 0
    var restorables: [ItemResult] = []
    var restoredMessage: String?

    /// Pulls every restorable item of this clean back out of the Trash and
    /// returns the toast that reports the outcome.
    func performUndo() -> FreedToast {
        var restored = 0
        for result in restorables {
            guard let from = result.trashedTo else { continue }
            if TrashRestore.restore(target: result.item.target, from: from) == nil {
                restored += 1
            }
        }
        let text = restored == 0
            ? "Nothing could be restored — the Trash may have been emptied."
            : "Restored \(restored) item\(restored == 1 ? "" : "s") from the Trash."
        return FreedToast(freed: freed, restoredMessage: text)
    }
}

/// The capsule toast itself: freed bytes + Undo, or the undo outcome.
struct FreedToastView: View {
    let toast: FreedToast
    var onUndo: () -> Void
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let restored = toast.restoredMessage {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .foregroundStyle(.blue)
                Text(restored)
                    .font(.callout.weight(.medium))
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Freed \(ByteFormat.string(toast.freed))")
                    .font(.callout.weight(.semibold).monospacedDigit())
                if !toast.restorables.isEmpty {
                    Button("Undo", action: onUndo)
                        .buttonStyle(.link)
                        .help("Moves everything from this clean back out of the Trash.")
                }
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.18)))
        .padding(.bottom, 16)
    }
}

/// Shown while an .app is being dragged over the window.
struct DropTargetOverlay: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.accent.opacity(0.08))
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Theme.accent.opacity(0.55),
                              style: StrokeStyle(lineWidth: 2.5, dash: [10, 7]))
            VStack(spacing: 10) {
                Image(systemName: "trash.square")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(Theme.accent)
                Text("Drop to uninstall")
                    .font(.title3.weight(.semibold))
                Text("Full removal preview first — nothing happens without your OK")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        .padding(14)
        .allowsHitTesting(false)
    }
}
