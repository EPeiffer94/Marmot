import SwiftUI
import AppKit

/// Marmot Wrapped: your cleaning stats as a shareable card.
struct WrappedView: View {

    let stats: WrappedStats
    var onClose: () -> Void

    @State private var copied = false

    var body: some View {
        VStack(spacing: 14) {
            card
            HStack(spacing: 10) {
                Button {
                    copyImage()
                } label: {
                    Label(copied ? "Copied!" : "Copy Image", systemImage: "doc.on.clipboard")
                }
                Button {
                    savePNG()
                } label: {
                    Label("Save PNG…", systemImage: "square.and.arrow.down")
                }
                Spacer()
                Button("Done") { onClose() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 460)
    }

    // MARK: The card itself (this exact view gets rendered to the PNG)

    private var card: some View {
        WrappedCard(stats: stats)
    }

    // MARK: Export

    @MainActor
    private func renderImage() -> NSImage? {
        let renderer = ImageRenderer(content: WrappedCard(stats: stats))
        renderer.scale = 2
        return renderer.nsImage
    }

    private func copyImage() {
        guard let image = renderImage() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
    }

    private func savePNG() {
        guard let image = renderImage(),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Marmot-Wrapped.png"
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        if panel.runModal() == .OK, let url = panel.url {
            try? png.write(to: url)
        }
    }
}

/// The rendered card — kept as its own view so ImageRenderer captures
/// exactly what's on screen.
struct WrappedCard: View {

    let stats: WrappedStats

    var body: some View {
        VStack(spacing: 16) {
            Text("🐿️")
                .font(.system(size: 52))
            Text("Marmot Wrapped")
                .font(.title2.weight(.bold))

            Text(ByteFormat.string(stats.totalFreed))
                .font(.system(size: 52, weight: .heavy).monospacedDigit())
            Text("freed and counting")
                .font(.callout)
                .opacity(0.75)

            VStack(spacing: 8) {
                statRow(icon: "trash", text: "\(stats.itemCount.formatted()) items cleaned")
                statRow(icon: "calendar", text: "across \(stats.activeDays) cleaning day\(stats.activeDays == 1 ? "" : "s")")
                if let top = stats.topTool {
                    statRow(icon: "star", text: "busiest tool: \(top.name) (\(ByteFormat.string(top.freed)))")
                }
                if stats.autopilotFreed > 0 {
                    statRow(icon: "clock.badge.checkmark",
                            text: "Autopilot freed \(ByteFormat.string(stats.autopilotFreed)) while I did nothing")
                }
                if let biggest = stats.biggest {
                    statRow(icon: "trophy",
                            text: "biggest win: \(biggest.name) (\(ByteFormat.string(biggest.size)))")
                }
            }
            .padding(.horizontal, 8)

            Text("Marmot — the free, open-source Mac cleaner\ngithub.com/EPeiffer94/Marmot")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .opacity(0.7)
        }
        .padding(28)
        .frame(width: 420)
        .background(
            LinearGradient(colors: [
                Color.pink.opacity(0.35),
                Color.mint.opacity(0.35),
                Color.blue.opacity(0.35)
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.primary.opacity(0.1))
        )
    }

    private func statRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 18)
                .opacity(0.8)
            Text(text)
                .font(.callout.weight(.medium))
            Spacer(minLength: 0)
        }
    }
}
