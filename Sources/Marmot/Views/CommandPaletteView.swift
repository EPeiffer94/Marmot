import SwiftUI

struct PaletteItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void
}

/// ⌘K command palette: type to jump to any module or run an action.
struct CommandPaletteView: View {

    let items: [PaletteItem]
    var onClose: () -> Void

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var filtered: [PaletteItem] {
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.subtitle.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Type a command or destination…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .focused($searchFocused)
                        .onSubmit { runFirst() }
                    Badge(text: "esc")
                }
                .padding(12)

                Divider()

                if filtered.isEmpty {
                    Text("No matches")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .padding(24)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(filtered.prefix(8).enumerated()), id: \.element.id) { index, item in
                                Button {
                                    item.action()
                                    onClose()
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: item.icon)
                                            .foregroundStyle(.tint)
                                            .frame(width: 22)
                                        VStack(alignment: .leading, spacing: 0) {
                                            Text(item.title)
                                                .font(.callout.weight(.medium))
                                            Text(item.subtitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        if index == 0 {
                                            Badge(text: "↩")
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .frame(maxHeight: 320)
                }
            }
            .frame(width: 480)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.primary.opacity(0.1))
            )
            .shadow(radius: 24, y: 8)
        }
        .onAppear { searchFocused = true }
        .onExitCommand { onClose() }
    }

    private func runFirst() {
        guard let first = filtered.first else { return }
        first.action()
        onClose()
    }
}
