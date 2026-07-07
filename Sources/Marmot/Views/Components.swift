import SwiftUI

// MARK: - Risk badge

struct RiskBadge: View {
    let risk: RiskLevel

    var color: Color {
        switch risk {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }

    var body: some View {
        Text(risk.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - Percent bar

struct PercentBar: View {
    let percent: Double        // 0...100
    var color: Color = .accentColor

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.primary.opacity(0.08))
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.gradient)
                    .frame(width: max(0, geo.size.width * min(percent, 100) / 100))
            }
        }
        .frame(height: 7)
        .animation(.easeOut(duration: 0.4), value: percent)
    }
}

// MARK: - Sparkline for network history

struct Sparkline: View {
    let values: [Double]
    var color: Color = .blue

    var body: some View {
        GeometryReader { geo in
            let maxValue = max(values.max() ?? 1, 1)
            Path { path in
                guard values.count > 1 else { return }
                let stepX = geo.size.width / CGFloat(values.count - 1)
                for (i, v) in values.enumerated() {
                    let x = CGFloat(i) * stepX
                    let y = geo.size.height * (1 - CGFloat(v / maxValue))
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(color.gradient, lineWidth: 1.5)
        }
    }
}

// MARK: - Proportional size bar ("what will change" visual)

struct GroupShare: Identifiable {
    let id = UUID()
    let name: String
    let bytes: Int64
    let color: Color
}

struct ProportionBar: View {
    let shares: [GroupShare]

    var total: Int64 { max(shares.reduce(0) { $0 + $1.bytes }, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(shares) { share in
                        Rectangle()
                            .fill(share.color.gradient)
                            .frame(width: max(2, geo.size.width * CGFloat(share.bytes) / CGFloat(total)))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 10)

            // Legend
            FlowLegend(shares: shares)
        }
    }
}

struct FlowLegend: View {
    let shares: [GroupShare]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(shares.prefix(6)) { share in
                HStack(spacing: 4) {
                    Circle().fill(share.color).frame(width: 7, height: 7)
                    Text("\(share.name) \(ByteFormat.string(share.bytes))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Shared palette

enum Palette {
    static let colors: [Color] = [.blue, .teal, .orange, .purple, .pink, .indigo, .mint, .yellow, .cyan, .red]

    static func color(for index: Int) -> Color {
        colors[index % colors.count]
    }
}

// MARK: - Empty state

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 42))
                .foregroundStyle(.tertiary)
            Text(title).font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
