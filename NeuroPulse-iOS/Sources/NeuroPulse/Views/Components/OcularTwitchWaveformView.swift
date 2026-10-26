import SwiftUI
import CoreGraphics

private struct WaveformPlotter {
    let size: CGSize
    let rangeDeg: Double
    let timeSpan: Double

    func x(_ time: Double) -> CGFloat { CGFloat(time / timeSpan) * size.width }
    func y(_ degrees: Double) -> CGFloat {
        CGFloat(0.5 - degrees / (2 * rangeDeg)) * size.height
    }
}

/// Recorded horizontal gaze and target paths, with inspection of actual saved samples.
public struct OcularTwitchWaveformView: View {
    public let recording: ExamRecording

    public enum DisplayedPhase: String, CaseIterable, Identifiable {
        case pursuit = "Moving dot"
        case holdRight = "Right dot"
        case holdLeft = "Left dot"
        public var id: String { rawValue }
    }

    @Environment(\.dynamicTypeSize) private var textSize
    @State private var selectedPhase: DisplayedPhase = .pursuit
    @State private var selectedTime: Double?
    @State private var showingMovements = false

    public init(recording: ExamRecording) { self.recording = recording }

    private var activeTrace: [TraceSample] {
        switch selectedPhase {
        case .pursuit: return recording.pursuit
        case .holdRight: return recording.holdRight
        case .holdLeft: return recording.holdLeft
        }
    }

    private var activeSaccades: [SaccadeEvent] {
        switch selectedPhase {
        case .pursuit: return recording.pursuitSaccades
        case .holdRight: return recording.holdRightSaccades
        case .holdLeft: return recording.holdLeftSaccades
        }
    }

    private var timeSpan: Double {
        max(activeTrace.map(\.t).filter(\.isFinite).max() ?? 0,
            selectedPhase == .pursuit ? AppConstants.Timing.smoothPursuitDurationSeconds : AppConstants.Timing.lateralHoldDurationSeconds)
    }

    // Fit the saved target and eye samples instead of clipping them to a fixed ±10° window.
    private var rangeDeg: Double {
        let values = activeTrace.flatMap { [$0.targetXDeg, $0.eyeXDeg].compactMap { $0 } }
        let largest = values.filter(\.isFinite).map(abs).max() ?? 0
        return max(4, ceil(largest * 1.15 / 2) * 2)
    }

    private var inspectedSample: TraceSample? {
        guard let selectedTime else { return nil }
        return activeTrace.filter { $0.t.isFinite }.min { abs($0.t - selectedTime) < abs($1.t - selectedTime) }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your eyes and the dot")
                .font(.title3.weight(.bold))
                .foregroundStyle(NeuroPulseColor.clinicalWhite)

            phasePickerLayout {
                ForEach(DisplayedPhase.allCases) { phase in
                    Button { selectedPhase = phase } label: {
                        Text(phase.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(selectedPhase == phase ? NeuroPulseColor.pantoneYellow : NeuroPulseColor.obsidianBase)
                            .foregroundStyle(selectedPhase == phase ? NeuroPulseColor.pantoneBlue : NeuroPulseColor.mutedSlate)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedPhase == phase ? .isSelected : [])
                }
            }

            if activeTrace.isEmpty {
                Text("No samples were saved for this task.")
                    .font(.subheadline)
                    .foregroundStyle(NeuroPulseColor.mutedSlate)
                    .padding(.vertical, 30)
            } else {
                graph
                legend
                Text(selectedPhase == .pursuit
                     ? "Similar shape and timing mean the estimates followed the dot's movement. A gap between lines can also come from calibration error."
                     : "The dashed line stays at the side dot. A steadier white line means less change in the estimated gaze position. Its distance from the dot also depends on calibration.")
                    .font(.subheadline)
                    .foregroundStyle(NeuroPulseColor.clinicalWhite)
                    .fixedSize(horizontal: false, vertical: true)

                if let sample = inspectedSample {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("At \(String(format: "%.2f", sample.t)) seconds")
                            .font(.subheadline.weight(.semibold))
                        Text("Dot: \(direction(sample.targetXDeg)) · Eyes: \(sample.eyeXDeg.map(direction) ?? "not captured")")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(NeuroPulseColor.clinicalWhite)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NeuroPulseColor.obsidianBase)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Text("Tap the graph to inspect a moment. Gaps mean tracking was missing.")
                        .font(.caption)
                        .foregroundStyle(NeuroPulseColor.mutedSlate)
                        .fixedSize(horizontal: false, vertical: true)
                }

                DisclosureGroup("Quick movements marked: \(activeSaccades.count)", isExpanded: $showingMovements) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Red bands mark fast changes in the eye estimate. Eye corrections and camera noise can both contribute.")
                            .font(.caption)
                        if selectedPhase != .pursuit {
                            Text("The summary count skips the first half-second while eyes move onto the side dot. This graph also shows movements during that settling time.")
                                .font(.caption)
                        }
                        ForEach(Array(activeSaccades.enumerated()), id: \.offset) { item in
                            Text("\(String(format: "%.2f", item.element.startTime)) s · \(String(format: "%.1f", item.element.amplitudeDeg))° movement · \(String(format: "%.0f", item.element.peakVelocityDegPerSec))°/s peak speed")
                                .font(.caption.monospacedDigit())
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 8)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(NeuroPulseColor.mutedSlate)
                .tint(NeuroPulseColor.mutedSlate)
            }
        }
        .clinicalCard()
        .onChange(of: selectedPhase) { _, _ in
            selectedTime = nil
            showingMovements = false
        }
    }

    private var phasePickerLayout: AnyLayout {
        textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 6))
            : AnyLayout(HStackLayout(spacing: 6))
    }

    private var graph: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                VStack(alignment: .trailing) {
                    Text("Right\n+\(String(format: "%.0f", rangeDeg))°")
                    Spacer()
                    Text("Center")
                    Spacer()
                    Text("Left\n−\(String(format: "%.0f", rangeDeg))°")
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(NeuroPulseColor.mutedSlate)
                .multilineTextAlignment(.trailing)
                .frame(width: 40)

                GeometryReader { proxy in
                    let plotter = WaveformPlotter(size: proxy.size, rangeDeg: rangeDeg, timeSpan: timeSpan)
                    ZStack {
                        Path { path in
                            for level in [-rangeDeg / 2, 0, rangeDeg / 2] {
                                path.move(to: CGPoint(x: 0, y: plotter.y(level)))
                                path.addLine(to: CGPoint(x: proxy.size.width, y: plotter.y(level)))
                            }
                        }
                        .stroke(NeuroPulseColor.mutedSlate.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                        ForEach(Array(activeSaccades.enumerated()), id: \.offset) { item in
                            let start = plotter.x(item.element.startTime)
                            let end = max(plotter.x(item.element.endTime), start + 3)
                            Rectangle()
                                .fill(Color(hex: "D62E2F").opacity(0.22))
                                .frame(width: end - start, height: proxy.size.height)
                                .position(x: (start + end) / 2, y: proxy.size.height / 2)
                        }
                        curve(plotter: plotter, isTarget: true)
                            .stroke(NeuroPulseColor.pantoneYellow, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        curve(plotter: plotter, isTarget: false)
                            .stroke(NeuroPulseColor.clinicalWhite, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                        if let sample = inspectedSample {
                            Path { path in
                                path.move(to: CGPoint(x: plotter.x(sample.t), y: 0))
                                path.addLine(to: CGPoint(x: plotter.x(sample.t), y: proxy.size.height))
                            }
                            .stroke(Color(hex: "D62E2F"), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        }
                    }
                    .background(NeuroPulseColor.obsidianBase)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        selectedTime = min(max(Double(location.x / proxy.size.width) * timeSpan, 0), timeSpan)
                    }
                }
            }
            .frame(height: 190)

            HStack {
                Text("0 s")
                Spacer()
                Text("\(String(format: "%.1f", timeSpan / 2)) s")
                Spacer()
                Text("\(String(format: "%.1f", timeSpan)) s")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(NeuroPulseColor.mutedSlate)
            .padding(.leading, 46)
            Text("Horizontal gaze position over time")
                .font(.caption)
                .foregroundStyle(NeuroPulseColor.mutedSlate)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Horizontal gaze position over time for the \(selectedPhase.rawValue.lowercased()) task. Dashed line is the dot; solid line is the eye estimate.")
        .accessibilityValue("\(activeTrace.count) recorded samples over \(String(format: "%.1f", timeSpan)) seconds, shown from \(String(format: "%.0f", rangeDeg)) degrees left to \(String(format: "%.0f", rangeDeg)) degrees right.")
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Dashed cream line: the dot", systemImage: "line.diagonal")
                .foregroundStyle(NeuroPulseColor.pantoneYellow)
            Label("Solid white line: estimated eye position", systemImage: "eye")
                .foregroundStyle(NeuroPulseColor.clinicalWhite)
        }
        .font(.caption.weight(.medium))
    }

    private func curve(plotter: WaveformPlotter, isTarget: Bool) -> Path {
        Path { path in
            var previousTime: Double?
            for sample in activeTrace {
                let value = isTarget ? Optional(sample.targetXDeg) : sample.eyeXDeg
                guard let value, value.isFinite, sample.t.isFinite else {
                    previousTime = nil
                    continue
                }
                let point = CGPoint(x: plotter.x(sample.t), y: plotter.y(value))
                if let previous = previousTime, sample.t > previous, sample.t - previous <= 0.1 {
                    path.addLine(to: point)
                } else {
                    path.move(to: point)
                }
                previousTime = sample.t
            }
        }
    }

    private func direction(_ degrees: Double) -> String {
        guard degrees.isFinite else { return "not captured" }
        if abs(degrees) < 0.05 { return "center" }
        return "\(String(format: "%.1f", abs(degrees)))° \(degrees < 0 ? "left" : "right")"
    }
}
