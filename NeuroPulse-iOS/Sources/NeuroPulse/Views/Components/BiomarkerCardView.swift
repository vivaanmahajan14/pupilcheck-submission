import SwiftUI

/// Explains an experimental measurement and its descriptive difference from a personal baseline.
public struct BiomarkerCardView: View {
    public let data: BiomarkerCardData
    public let showsBaselineComparison: Bool
    @ScaledMetric(relativeTo: .title) private var valueSize: CGFloat = 30

    public init(data: BiomarkerCardData, showsBaselineComparison: Bool = true) {
        self.data = data
        self.showsBaselineComparison = showsBaselineComparison
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(displayTitle)
                .font(.headline)
                .foregroundStyle(NeuroPulseColor.pantoneBlue)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(formatted(data.measuredValue))
                    .font(.system(size: valueSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(NeuroPulseColor.pantoneBlue)
                if !data.unit.isEmpty {
                    Text(data.unit == "events" ? "movements" : data.unit)
                        .font(.subheadline)
                        .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.68))
                }
            }

            Text(explanation)
                .font(.subheadline)
                .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)

            if showsBaselineComparison, let baseline = data.baselineValue {
                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Saved baseline: \(formatted(baseline)) \(data.unit)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.70))
                        comparisonBadge
                    }
                    Text(difference(from: baseline))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(differenceTextColor(for: data.status))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(differenceBackgroundColor(for: data.status))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(differenceBorderColor(for: data.status), lineWidth: 1)
                )
            } else if !showsBaselineComparison || data.baselineValue == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text(showsBaselineComparison ? "No compatible personal baseline for this measurement." : "Personal reference for future recordings; not a healthy-range assessment.")
                        .font(.caption)
                        .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.72))
                    Text("RECORDING ONLY · NO PERSONAL COMPARISON")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(NeuroPulseColor.pantoneBlue)

                }
                .padding(10)
                .background(NeuroPulseColor.pantoneBlueSurface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .appSurface()
    }

    private func differenceBackgroundColor(for status: TriageStatus) -> Color { NeuroPulseColor.pantoneYellowCanvas }
    private func differenceBorderColor(for status: TriageStatus) -> Color { NeuroPulseColor.pantoneBlue.opacity(0.25) }
    private func differenceTextColor(for status: TriageStatus) -> Color { NeuroPulseColor.pantoneBlue }

    private var comparisonBadge: some View {
        Label("PERSONAL COMPARISON", systemImage: "arrow.left.arrow.right")
            .font(.caption2.weight(.bold))
            .foregroundStyle(NeuroPulseColor.pantoneBlue)
    }

    private func formatted(_ value: Double) -> String {
        guard value.isFinite else { return "Unavailable" }
        if data.unit == "events" { return String(format: "%.0f", value) }
        if data.unit == "ms" || data.unit == "%" { return String(format: "%.1f", value) }
        return String(format: "%.2f", value)
    }

    private func difference(from baseline: Double) -> String {
        RecordingOverview.eyeMeasurementComparison(value: data.measuredValue, baseline: baseline, unit: data.unit)
    }

    private var metric: Int {
        // Units distinguish pursuit gain from pursuit lag, including older saved titles.
        switch data.unit {
        case "ms": return 1
        case "%": return 2
        case "ratio": return 0
        case "°/s": return 3
        case "events": return 4
        default: return 5
        }
    }

    var displayTitle: String {
        switch metric {
        case 0: return "Tracking speed ratio"
        case 1: return "Timing offset"
        case 2: return "Time near the hold dot"
        case 3: return "Drift toward center"
        case 4: return "Quick eye movements"
        default: return data.title
        }
    }

    var explanation: String {
        switch metric {
        case 0:
            return "1.00 means matching eye and dot speed ranges. Below 1.00 means a smaller range; above 1.00 means a larger range. This ratio alone does not describe smoothness."
        case 1:
            let amount = String(format: "%.1f", abs(data.measuredValue))
            let timing = data.measuredValue < 0
                ? "The estimated eye trace led the dot by \(amount) milliseconds."
                : "The estimated eye trace followed the dot by \(amount) milliseconds."
            return timing + " Camera and screen delays also affect this estimate; it is not a reaction-time test."
        case 2:
            return "Percentage of usable side-hold estimates within \(String(format: "%.1f", AppConstants.Norms.fixationRadiusDeg))° of the dot. 0% means none fell inside that area. Calibration offset can lower this even when you look at the dot; this is not a pass/fail score."
        case 3:
            return "Estimated slow drift back toward the center during the side holds. Lower means less inward drift in this recording."
        case 4:
            return "Fast changes detected across the tasks, excluding the first half-second of each side hold. Normal corrections and camera noise can contribute; this is not a symptom count."
        default:
            return "An experimental estimate from this recording."
        }
    }
}
