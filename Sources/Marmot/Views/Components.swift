import SwiftUI

// MARK: - Badge (capsule tag used everywhere)

struct Badge: View {
    let text: String
    var color: Color = .secondary

    init(text: String, color: Color = .secondary) {
        self.text = text
        self.color = color
    }

    init(risk: RiskLevel) {
        self.init(text: risk.label, color: risk.color)
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - Shared color/format extensions

extension RiskLevel {
    var color: Color {
        switch self {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }
}

extension SystemSnapshot {
    var healthColor: Color {
        if healthScore >= 80 { return .green }
        if healthScore >= 50 { return .orange }
        return .red
    }
}
// (HealthRing below derives its own color from the same thresholds.)

extension ByteFormat {
    static func rate(_ bytesPerSec: Double) -> String {
        string(Int64(max(bytesPerSec, 0))) + "/s"
    }
}

extension ItemOutcome {
    var icon: String {
        switch self {
        case .done: return "checkmark.circle.fill"
        case .wouldRemove, .wouldRun: return "eye"
        case .skippedUnsafe, .skippedWhitelisted: return "shield.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .done: return .green
        case .wouldRemove, .wouldRun: return .blue
        case .skippedUnsafe, .skippedWhitelisted: return .orange
        case .failed: return .red
        }
    }
}

// MARK: - Start screen (shared scan-module opener)

struct StartScreen<Extra: View>: View {
    let icon: String
    let title: String
    let message: String
    let buttonLabel: String
    let tint: Color
    let action: () -> Void
    let extra: Extra

    init(icon: String, title: String, message: String, buttonLabel: String,
         tint: Color = Theme.accent,
         action: @escaping () -> Void,
         @ViewBuilder extra: () -> Extra) {
        self.icon = icon
        self.title = title
        self.message = message
        self.buttonLabel = buttonLabel
        self.tint = tint
        self.action = action
        self.extra = extra()
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Theme.wash(tint))
                    .frame(width: 118, height: 118)
                Image(systemName: icon)
                    .font(.system(size: 46))
                    .foregroundStyle(tint.gradient)
            }
            Text(title)
                .font(.largeTitle.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            extra
            Button(action: action) {
                Label(buttonLabel, systemImage: "magnifyingglass")
                    .frame(width: 200)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(tint)
            Spacer()
            Spacer().frame(height: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension StartScreen where Extra == EmptyView {
    init(icon: String, title: String, message: String, buttonLabel: String,
         tint: Color = Theme.accent,
         action: @escaping () -> Void) {
        self.init(icon: icon, title: title, message: message,
                  buttonLabel: buttonLabel, tint: tint, action: action) { EmptyView() }
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
                    if i == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
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

// MARK: - Card chrome (shared by Dashboard and Live Status)

extension View {
    /// Neutral card by default; pass a tint for a soft pastel wash.
    func cardStyle(tint: Color? = nil) -> some View {
        background(
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.primary.opacity(0.035))
                if let tint {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Theme.wash(tint))
                }
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.primary.opacity(0.06))
            }
        )
    }
}

// MARK: - Health ring

struct HealthRing: View {
    let score: Int
    var lineWidth: CGFloat = 8
    var caption: String? = nil

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(score)")
                    .font(.title2.weight(.bold).monospacedDigit())
                if let caption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .animation(.easeOut, value: score)
    }

    private var color: Color {
        if score >= 80 { return .green }
        if score >= 50 { return .orange }
        return .red
    }
}

// MARK: - Loading placeholder

struct LoadingState: View {
    let text: String

    var body: some View {
        ProgressView(text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
