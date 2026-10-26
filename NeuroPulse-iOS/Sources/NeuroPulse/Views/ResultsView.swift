import SwiftUI
import Charts

/// Plain-language view of a saved experimental eye-tracking recording.
public struct ResultsView: View {
    public let result: SCAT6TriageResult
    public let onDone: () -> Void
    public let onContinueToMotorTests: (() -> Void)?
    private let suppliedMotorSession: MotorTestSession?
    private let doneTitle: String
    private let onClose: () -> Void
    private let isUnsavedMotorReview: Bool
    @ObservedObject private var manager = BaselineManager.shared

    @State private var showingResponseGuide = false
    @State private var showingQuality = false

    public init(result: SCAT6TriageResult, onDone: @escaping () -> Void, onContinueToMotorTests: (() -> Void)? = nil, motorSession: MotorTestSession? = nil, doneTitle: String = "Done", onClose: (() -> Void)? = nil, isUnsavedMotorReview: Bool = false) {
        self.result = result
        self.onDone = onDone
        self.onContinueToMotorTests = onContinueToMotorTests
        self.suppliedMotorSession = motorSession
        self.doneTitle = doneTitle
        self.onClose = onClose ?? onDone
        self.isUnsavedMotorReview = isUnsavedMotorReview
    }

    public var body: some View {
        ZStack {
            NeuroPulseColor.pantoneYellowCanvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if !result.isBaselineTest { coachAction }
                    sessionOverview
                    if motorSession == nil, onContinueToMotorTests != nil {
                        Text("Eye recording finished. Reaction, tapping, and standing are next—tap Continue below.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(NeuroPulseColor.pantoneBlue)
                    }
                    DisclosureGroup("Graphs, measurements & recording quality") {
                        VStack(alignment: .leading, spacing: 18) {
                    comparisonSummary

                    if let recording = result.recording {
                        OcularTwitchWaveformView(recording: recording)
                        recordingContext(recording)
                    }

                    VStack(alignment: .leading, spacing: 11) {
                        Text("1 & 2 · EYE MOVEMENT")
                            .font(.caption.weight(.bold))
                            .tracking(1)
                            .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.58))
                        if RecordingOverview.canUseEyeReference(result) {
                            ForEach(result.biomarkers) { metric in
                                BiomarkerCardView(data: metric, showsBaselineComparison: !result.isBaselineTest)
                            }
                        } else {
                            Text("Eye measurements are withheld from comparison because recording quality needs attention. Review the quality details before repeating.")
                                .font(.subheadline)
                                .foregroundStyle(NeuroPulseColor.pantoneBlue)
                        }
                    }

                    if let motorSession {
                        MotorResultsSection(session: motorSession)
                    } else {
                        Text("Tests 3 & 4 have not been saved for this recording.")
                            .font(.subheadline)
                            .foregroundStyle(NeuroPulseColor.pantoneBlue)
                    }

                    if let recording = result.recording {
                        if let quality = recording.qualityMetadata {
                            DisclosureGroup("Recording quality", isExpanded: $showingQuality) {
                                qualityDetails(recording: recording, quality: quality)
                                    .padding(.top, 12)
                            }
                            .font(.headline)
                            .foregroundStyle(NeuroPulseColor.pantoneBlue)
                            .tint(NeuroPulseColor.pantoneBlue)
                            .appSurface()
                        }
                    }

                        }.padding(.top, 12)
                    }
                    .font(.headline)
                    .tint(NeuroPulseColor.pantoneBlue)
                    .foregroundStyle(NeuroPulseColor.pantoneBlue)

                    if result.isBaselineTest { safetyNote }

                    if result.isBaselineTest {
                        Button { showingResponseGuide = true } label: {
                            Label("Open head injury response guide", systemImage: "cross.case.fill")
                                .font(.headline)
                                .foregroundStyle(NeuroPulseColor.pantoneRed)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(NeuroPulseColor.cardWhite)
                                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
                .frame(maxWidth: 660)
                .frame(maxWidth: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            resultActions
        }
        .sheet(isPresented: $showingResponseGuide) {
            HeadInjuryResponseGuideView()
        }
        .preferredColorScheme(.light)

    }

    private var resultActions: some View {
        VStack(spacing: 10) {
            if motorSession == nil, let onContinueToMotorTests {
                Button(action: onContinueToMotorTests) {
                    Label("Continue to tests 3 & 4", systemImage: "arrow.right")
                        .font(.headline)
                        .foregroundStyle(NeuroPulseColor.cardWhite)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .padding(14)
                        .background(NeuroPulseColor.pantoneBlue, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
            Button(action: onDone) {
                Text(doneTitle)
                    .font(.headline)
                    .foregroundStyle(motorSession == nil && onContinueToMotorTests != nil
                        ? NeuroPulseColor.pantoneBlue : NeuroPulseColor.cardWhite)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(motorSession == nil && onContinueToMotorTests != nil
                        ? Color.clear : NeuroPulseColor.pantoneBlue, in: RoundedRectangle(cornerRadius: 14))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: 660)
        .frame(maxWidth: .infinity)
        .background(NeuroPulseColor.pantoneYellowCanvas)
        .overlay(alignment: .top) { Divider() }
    }

    private var motorSession: MotorTestSession? {
        suppliedMotorSession ?? manager.motorSession(athleteId: result.athleteId, eyeResultID: result.id)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(isUnsavedMotorReview ? "REVIEW BEFORE SAVING" : (result.isBaselineTest ? (RecordingOverview.canUseEyeReference(result) ? "EYE BASELINE SAVED" : "BASELINE ATTEMPT SAVED") : "RECORDING SAVED"))
                    .font(.caption.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.62))
                Text(result.athleteName)
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .tracking(-0.6)
                    .foregroundStyle(NeuroPulseColor.pantoneBlue)
                Text(formatDate(result.timestamp))
                    .font(.subheadline)
                    .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.68))
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(NeuroPulseColor.pantoneBlue)
                    .frame(width: 44, height: 44)
                    .background(NeuroPulseColor.cardWhite)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Close recording results")
        }
    }

    private var coachAction: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("If an injury is suspected", systemImage: "cross.case.fill")
                .font(.headline)
            Text(result.sidelineActionGuidance)
                .font(.subheadline)
            Button { showingResponseGuide = true } label: {
                Label("Signs & next steps", systemImage: "arrow.up.right")
                    .font(.headline)
                    .foregroundStyle(NeuroPulseColor.pantoneRed)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(NeuroPulseColor.pantoneBlue)
        .appSurface()
    }

    private var sessionOverview: some View {
        FourTestOverviewView(items: RecordingOverview.items(eye: result, motor: motorSession))
    }

    private var comparisonSummary: some View {
        let hasBaseline = result.biomarkers.contains { $0.baselineValue != nil }
        let mismatch = result.biomarkers.compactMap(\.comparisonNote).first
        return VStack(alignment: .leading, spacing: 7) {
            Label(
                result.isBaselineTest ? (RecordingOverview.canUseEyeReference(result) ? "Eye measurements saved as a personal reference." : "Eye recording saved in history; the eye reference was not replaced.") : (hasBaseline ? "Compared with the saved personal reference." : "Recording only · no compatible eye baseline saved."),
                systemImage: result.isBaselineTest ? "bookmark.fill" : (hasBaseline ? "person.crop.circle.badge.checkmark" : "person.3.fill")
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(NeuroPulseColor.pantoneBlue)
            .fixedSize(horizontal: false, vertical: true)

            Text(result.isBaselineTest
                 ? (RecordingOverview.canUseEyeReference(result) ? "Future eye recordings can show changes from this reference under the same setup." : "Repeat eye calibration before using this attempt as a reference. Any usable motor reference is handled separately when saved.")
                 : (hasBaseline ? "Each test below shows what you recorded and how it changed from your personal baseline." : "Save a personal baseline to compare future recordings made under the same conditions."))
                .font(.subheadline)
                .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.76))
                .fixedSize(horizontal: false, vertical: true)

            if !result.isBaselineTest, !hasBaseline, let mismatch {
                Text(mismatch)
                    .font(.caption)
                    .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.67))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NeuroPulseColor.pantoneBlueSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func recordingContext(_ recording: ExamRecording) -> some View {
        let quality = recording.qualityMetadata
        let lessPrecise = quality.map {
            $0.canvasRmsErrorPercent > AppConstants.Norms.maxValidationCanvasRmsPercent ||
            $0.worstTargetErrorPercent > AppConstants.Norms.maxValidationWorstTargetPercent
        } ?? false
        return VStack(alignment: .leading, spacing: 7) {
            Label(quality == nil ? "Calibration details unavailable" : (lessPrecise ? "Gaze position is less certain" : "Tracking captured"),
                  systemImage: lessPrecise ? "viewfinder" : "waveform.path")
                .font(.headline)
            if quality == nil || lessPrecise {
                Text(quality == nil
                 ? "This recording has no saved calibration-check details. Use the trace to explore what was captured and treat baseline comparisons cautiously."
                 : "The camera's estimate did not closely match the calibration-check dots. You can view the recording, but the graph and baseline differences may be distorted. Repeat with a steady phone before drawing conclusions.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("\(String(format: "%.0f", recording.validSampleFraction * 100))% usable samples · \(String(format: "%.0f", recording.measuredFrameRate)) frames/sec")
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(NeuroPulseColor.pantoneBlue)
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NeuroPulseColor.pantoneBlueSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func qualityDetails(recording: ExamRecording, quality: RecordingQualityMetadata) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            qualityRow("Average dot-position error", value: String(format: "%.1f%%", quality.canvasRmsErrorPercent))
            qualityRow("Largest dot-position error", value: String(format: "%.1f%%", quality.worstTargetErrorPercent))
            Text("These errors compare estimated gaze with the check dots in normalized screen coordinates. Lower means closer. They do not grade how well the player followed instructions.")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            qualityRow("Usable camera samples", value: String(format: "%.0f%%", recording.validSampleFraction * 100))
            Text("Samples remaining after unreadable eyes, blinks, tracking loss, or head movement were excluded. Gaps in the graph show missing measurements.")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            qualityRow("Captured frame rate", value: String(format: "%.1f frames/sec", recording.measuredFrameRate))
            if !quality.excludedReasons.isEmpty {
                Text("Sample exclusions: \(quality.excludedReasons.sorted().joined(separator: "; ")).")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.78))
    }

    private func qualityRow(_ title: String, value: String) -> some View {
        MeasurementRow(title: title, value: value)
    }

    private var safetyNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(NeuroPulseColor.pantoneBlue)
            Text("Experimental movement measurements only. This recording cannot diagnose a concussion or clear a player. If injury is suspected, follow the response guide and seek medical care.")
                .font(.subheadline)
                .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.76))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .background(NeuroPulseColor.cardWhite)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func formatDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

/// A descriptive overview shared by current and saved recordings.
struct FourTestOverviewView: View {
    let items: [TestOverviewItem]
    var body: some View {
        let count = items.filter(\.hasUsableData).count
        let pending = items.filter { $0.explanation.hasPrefix("Not recorded") }.count
        VStack(alignment: .leading, spacing: 16) {
            Text("Your four-test overview")
                .font(.title3.bold())
            Text("\(count) ready to review · \(items.count - count - pending) need attention · \(pending) not recorded")
                .font(.subheadline.weight(.semibold))
            Text("Ready means usable data, not a health assessment. Needs attention means a recording issue, not a detected injury.")
                .font(.caption)
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Label("\(item.id) · \(item.title)", systemImage: item.hasUsableData ? "waveform.path" : "info.circle")
                        .font(.headline)
                    Text(item.hasUsableData ? (item.explanation.components(separatedBy: ". ").first ?? "Measurements available") : (item.explanation.hasPrefix("Not recorded") ? "Not yet recorded" : "Needs review or repeat"))
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    DisclosureGroup(item.hasUsableData ? "Meaning & comparison" : "Why & next steps") {
                        Text(item.explanation)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 6)
                    }
                }
                if item.id != 4 { Divider() }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("What to do with these results").font(.subheadline.bold())
                Text("Compare using the same phone and setup. Differences show change, but the app cannot tell whether that change exceeds ordinary variation or is medically significant.")
                Text("For recording issues, open ‘Why & next steps.’ If injury is suspected, use the response guide and seek medical assessment—even if results match your baseline.")
            }
            .font(.footnote)
            .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(NeuroPulseColor.pantoneBlue)
        .fixedSize(horizontal: false, vertical: true)
        .appSurface()
    }

}

/// The same motor summary is used before saving and when reopening player history.
struct MotorResultsSection: View {
    let session: MotorTestSession
    private let blue = NeuroPulseColor.pantoneBlue

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            card("3 · Reaction & tapping", measurement: session.reaction, reference: session.reactionReference, reaction: true)
            card("4 · Standing phone movement", measurement: session.balance, reference: session.balanceReference, reaction: false)
        }
    }

    private func card(_ title: String, measurement: MotorMeasurement, reference suppliedReference: MotorReference?, reaction: Bool) -> some View {
        let reference = session.isBaseline == true ? nil : RecordingOverview.compatibleReference(suppliedReference, reaction: reaction)
        return VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: reaction ? "hand.tap" : "figure.stand")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            let interpretation = RecordingOverview.motorItem(measurement, reference: reference, baseline: session.isBaseline == true, reaction: reaction)
            Text(interpretation.explanation)
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            if interpretation.hasUsableData {
                if reaction {
                    let trials = (1...5).compactMap { index -> (Int, Double)? in
                        guard let value = measurement.metrics["reaction_trial_\(index)_ms"], value.isFinite, value >= 0 else { return nil }
                        return (index, value)
                    }
                    if !trials.isEmpty {
                        Chart {
                            ForEach(trials, id: \.0) { trial in
                                BarMark(x: .value("Trial", String(trial.0)), y: .value("Milliseconds", trial.1))
                                    .foregroundStyle(blue)
                            }
                            if let value = reference?.measurement.metrics["median_reaction_ms"], value.isFinite, reference?.protocolVersion == "motor-1" {
                                RuleMark(y: .value("Baseline median", value))
                                    .foregroundStyle(blue).lineStyle(StrokeStyle(lineWidth: 2, dash: [5]))
                            }
                        }
                        .chartYAxisLabel("Reaction time (ms)").frame(height: 180)
                        .padding(.vertical, 8)
                        .accessibilityLabel("Reaction trial times in milliseconds. The dashed line is the saved baseline median, when available.")
                    }
                    metric("Typical reaction", key: "median_reaction_ms", unit: "ms", measurement: measurement, reference: reference)
                    metric("Alternating taps", key: "alternations_per_second", unit: "/sec", measurement: measurement, reference: reference)
                    metric("Early taps", key: "early_taps", unit: "", measurement: measurement, reference: nil)
                    metric("Missed cues", key: "missed_trials", unit: "", measurement: measurement, reference: nil)
                    metric("Same-side tapping errors", key: "same_side_errors", unit: "", measurement: measurement, reference: nil)
                    Text("Each bar is one cue-to-tap time. Smaller means a quicker response on this phone. Tapping measures alternations per second using one finger; practice and screen/touch delay affect the numbers. Early taps happen before the cue, missed cues have no response, and same-side errors are repeated taps without switching pads.")
                } else {
                    let key = "phone_acceleration_rms_m_s2"
                    if let value = measurement.metrics[key], value.isFinite, value >= 0 {
                        Chart {
                            BarMark(x: .value("Recording", "This session"), y: .value("Movement", value)).foregroundStyle(blue)
                            if let baseline = reference?.measurement.metrics[key], baseline.isFinite, baseline >= 0, reference?.protocolVersion == "motor-1" {
                                BarMark(x: .value("Recording", "Baseline"), y: .value("Movement", baseline)).foregroundStyle(blue.opacity(0.65))
                            }
                        }
                        .chartYAxisLabel("Phone acceleration (m/s²)").frame(height: 170)
                        .padding(.vertical, 8)
                    }
                    metric("Phone acceleration", key: key, unit: "m/s²", measurement: measurement, reference: reference)
                    metric("Typical tilt", key: "phone_tilt_rms_deg", unit: "°", measurement: measurement, reference: reference)
                    metric("Rotation speed", key: "phone_rotation_rms_deg_s", unit: "°/sec", measurement: measurement, reference: reference)
                    Text("Larger values mean more phone movement during this attempt. Grip and placement affect it. These are phone measurements, not force-plate body sway or a clinical balance score.")
                }
                if session.isBaseline == true {
                    Label("Personal reference · this baseline session.", systemImage: "bookmark")
                } else if let reference, reference.protocolVersion == "motor-1" {
                    Text("Reference: \(reference.recordedAt.formatted(date: .abbreviated, time: .shortened)). Compare with the same phone and setup. Changes do not determine concussion risk.")
                } else {
                    Text("No compatible personal reference was saved for this test. Record it during a baseline session to compare future attempts.")
                }
            } else {
                Text("Unavailable measurements are excluded from the overview’s usable-test count and do not replace a personal reference.")
            }
        }
        .font(.subheadline)
        .foregroundStyle(blue)
        .appSurface()
    }

    @ViewBuilder private func metric(_ title: String, key: String, unit: String, measurement: MotorMeasurement, reference: MotorReference?) -> some View {
        if let value = measurement.metrics[key], value.isFinite {
            VStack(alignment: .leading, spacing: 5) {
                MeasurementRow(
                    title: title,
                    value: "\(value.formatted(.number.precision(.fractionLength(0...2)))) \(unit)".trimmingCharacters(in: .whitespaces)
                )
                if let delta = measurement.difference(for: key, from: reference) {
                    Text("\(delta >= 0 ? "+" : "")\(delta.formatted(.number.precision(.fractionLength(0...2)))) \(unit) from baseline")
                        .font(.caption)
                        .foregroundStyle(blue.opacity(0.76))
                }
            }
            .padding(12)
            .background(NeuroPulseColor.pantoneYellowCanvas, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
