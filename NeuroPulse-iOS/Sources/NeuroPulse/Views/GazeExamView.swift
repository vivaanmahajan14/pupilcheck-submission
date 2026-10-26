import SwiftUI

/// Guided eye setup, smooth pursuit recording, and lateral gaze holds.
/// Preserves the full-screen ARKit wireframe camera view throughout all phases.
public struct GazeExamView: View {
    @StateObject private var viewModel: ExamViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingResponseGuide = false
    @State private var showingCalibrationDiagnostics = false
    private let targetColor = Color(hex: "FCEEA8")

    public let onDismiss: () -> Void
    public let onContinueToMotorTests: ((SCAT6TriageResult) -> Void)?

    public init(
        athlete: AthleteProfile,
        isBaselineMode: Bool,
        tracker: (any GazeTrackerProtocol)? = nil,
        onDismiss: @escaping () -> Void,
        onContinueToMotorTests: ((SCAT6TriageResult) -> Void)? = nil
    ) {
        self._viewModel = StateObject(wrappedValue: ExamViewModel(athlete: athlete, isBaselineMode: isBaselineMode, tracker: tracker))
        self.onDismiss = onDismiss
        self.onContinueToMotorTests = onContinueToMotorTests
    }

    public var body: some View {
        ZStack {
            NeuroPulseColor.pantoneBlueDark
                .ignoresSafeArea()

            VStack(spacing: 10) {
                topNavigationBar

                progressBar

                phaseInstructionHeader

                mainCanvasContainer
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Results Sheet when complete
            if viewModel.currentPhase == .completed, let result = viewModel.triageResult {
                ResultsView(result: result, onDone: onDismiss, onContinueToMotorTests: onContinueToMotorTests.map { callback in { callback(result) } })
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .onAppear {
            viewModel.startExam()
        }
        .onDisappear {
            viewModel.cancelExam()
        }
        .sheet(isPresented: $showingResponseGuide) {
            HeadInjuryResponseGuideView()
        }
        .preferredColorScheme(viewModel.currentPhase == .completed ? .light : .dark)
    }

    // MARK: - Top Navigation Bar
    private var topNavigationBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(NeuroPulseColor.pantoneYellow)
                .frame(width: 40, height: 40)
                .background(NeuroPulseColor.pantoneYellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(NeuroPulseColor.pantoneYellow.opacity(0.45), lineWidth: 1))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(viewModel.selectedAthlete.name)
                    .font(.headline)
                    .foregroundColor(NeuroPulseColor.pantoneYellow)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(viewModel.isBaselineMode ? "Reference Recording" : "Active Check")
                    .font(.caption)
                    .foregroundColor(NeuroPulseColor.pantoneYellow.opacity(0.85))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            Button(action: { showingResponseGuide = true }) {
                Image(systemName: "cross.case.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(NeuroPulseColor.cardWhite)
                    .frame(width: 44, height: 44)
                    .background(NeuroPulseColor.pantoneRed)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Open head injury response guide")

            // Close Button
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(NeuroPulseColor.pantoneYellow)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Exit recording")
        }
        .buttonStyle(.plain)
    }

    // MARK: - Progress Bar
    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(NeuroPulseColor.pantoneYellow.opacity(0.15))
                    .frame(height: 4)

                RoundedRectangle(cornerRadius: 3)
                    .fill(NeuroPulseColor.pantoneYellow)
                    .frame(width: geo.size.width * CGFloat(viewModel.examProgressPercent / 100.0), height: 4)
                    .animation(reduceMotion ? nil : .linear(duration: 0.1), value: viewModel.examProgressPercent)
            }
        }
        .frame(height: 4)
    }

    // MARK: - Phase Header
    private var phaseInstructionHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(currentPhaseTitle.uppercased())
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundColor(NeuroPulseColor.pantoneYellow)
                    .tracking(0.5)

                Spacer()

                if case .calibration(let idx) = viewModel.currentPhase {
                    Text("Dot \(idx + 1) of \(viewModel.calibrationPoints.count)")
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundColor(NeuroPulseColor.pantoneYellow.opacity(0.75))

                }
            }

            Text(currentInstructionText)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(NeuroPulseColor.pantoneYellow.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .frame(height: 88, alignment: .topLeading)
    }

    private var currentPhaseTitle: String {
        if viewModel.isRecoveringTracking { return "Adjust the phone to resume" }
        switch viewModel.currentPhase {
        case .idle:
            return "Preparing sensors"
        case .alignmentAndDistanceCheck:
            return "Position your phone"
        case .calibration:
            return "Look at each bright dot"
        case .countdown(let c):
            return "Starting in (\(c)s)"
        case .smoothPursuit:
            return "Follow the moving dot"
        case .lateralHold:
            return "Look at the stationary dot"
        case .completed:
            return "Recording complete"
        case .invalid:
            return "Recording couldn't finish"
        }
    }

    private var currentInstructionText: String {
        switch viewModel.currentPhase {
        case .idle:
            return "Waiting for TrueDepth sensor..."
        case .alignmentAndDistanceCheck:
            return "Rest the phone on a support and face the camera. Setup advances automatically."
        case .calibration:
            return "Look at the bright center until the dot moves. Blink normally."
        case .countdown:
            return "Prepare to follow the moving dot smoothly across the screen."
        case .smoothPursuit:
            return "Follow the bright center smoothly. Keep your head comfortable and steady."
        case .lateralHold(let side, _):
            return "Keep looking at the stationary \(side.rawValue.lowercased()) target."
        case .completed:
            return "Compiling ocular telemetry and quality report..."
        case .invalid:
            return "The recording could not be finished."
        }
    }

    private var showsTrackingWarnings: Bool {
        switch viewModel.currentPhase {
        case .completed, .invalid, .idle: return false
        default: return true
        }
    }

    // MARK: - Main Canvas Container (Unified Full-Screen Live ARKit Viewport)
    private var mainCanvasContainer: some View {
        GeometryReader { geometry in
            ZStack {
                // 1. Live ARKit Camera Viewport with Face Mesh & Eye Highlights
                #if canImport(ARKit) && os(iOS)
                if let session = viewModel.tracker.arSession {
                    ARCameraPreviewView(session: session, showsWireframe: true)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(NeuroPulseColor.obsidianBase)
                }
                #else
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(NeuroPulseColor.obsidianBase)
                #endif

                // 2. Subtle Translucent Dark Layer for target contrast
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(NeuroPulseColor.pantoneBlue.opacity(0.32))

                // Canvas Border
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(NeuroPulseColor.pantoneYellow.opacity(0.35), lineWidth: 1.5)

                // 3. Active Phase Content
                switch viewModel.currentPhase {
                case .idle:
                    Text("Initializing TrueDepth front camera...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(NeuroPulseColor.pantoneYellow.opacity(0.6))

                case .alignmentAndDistanceCheck:
                    alignmentPhaseView(size: geometry.size)

                case .calibration(let index):
                    calibrationPhaseView(size: geometry.size, activeIndex: index)

                case .countdown(let count):
                    countdownPhaseView(count: count)

                case .smoothPursuit:
                    stimulusCanvasView(size: geometry.size)

                case .lateralHold(let side, _):
                    lateralHoldCanvasView(size: geometry.size, side: side)

                case .completed:
                    EmptyView()

                case .invalid(let reason):
                    invalidPhaseView(reason: reason)
                }

                // Overlay controls do not resize the calibrated target canvas.
                if viewModel.isRecoveringTracking {
                    VStack {
                        Spacer()
                        VStack(spacing: 10) {
                            Text("Tracking paused")
                                .font(.headline)
                            Text(viewModel.recordingHint ?? "Return to your starting phone and head position.")
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Recalibrate and restart eye tests") {
                                viewModel.restartEyeCalibration()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(NeuroPulseColor.pantoneYellow)
                            .foregroundStyle(NeuroPulseColor.pantoneBlueDark)
                            Text("Restarts both eye tasks and discards this unfinished eye recording.")
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(16)
                        .background(NeuroPulseColor.pantoneBlueDark.opacity(0.96), in: RoundedRectangle(cornerRadius: 14))
                        .padding(12)
                    }
                }

                if viewModel.awaitingTaskStart {
                    ScrollView {
                        VStack(spacing: 18) {
                            if case .countdown = viewModel.currentPhase,
                               let report = viewModel.bestValidationReport, !report.isAcceptable {
                                Text("Calibration needs another try").font(.title2.bold())
                                Text(String(format: "Average error: %.1f%% (limit %.0f%%)\nLargest error: %.1f%% (limit %.0f%%)",
                                    report.canvasRmsErrorPercent, AppConstants.Norms.maxValidationCanvasRmsPercent,
                                    report.worstTargetErrorPercent, AppConstants.Norms.maxValidationWorstTargetPercent))
                                Text("The camera estimate did not match the check dots closely enough. This is tracking accuracy, not a health result. Keep the phone supported and look at the white center of each bright dot.")
                                Button("Retry calibration") { viewModel.restartEyeCalibration() }
                                    .buttonStyle(.borderedProminent)
                                    .tint(NeuroPulseColor.pantoneYellow)
                                    .foregroundStyle(NeuroPulseColor.pantoneBlueDark)
                                DisclosureGroup("Calibration diagnostics", isExpanded: $showingCalibrationDiagnostics) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Positions are percentages of canvas width and height; (50, 50) is the center. Estimates outside 0–100 are off the canvas.")
                                        ForEach(viewModel.calibrationCheckDiagnostics, id: \.self) { Text($0) }
                                    }.font(.caption).padding(.top, 8)
                                }.tint(.white)
                                Button("Continue with low-quality eye estimates") { viewModel.beginPreparedTask() }
                                    .buttonStyle(.bordered)
                                Text("Continuing does not pass the check. Eye results will remain flagged; reaction and standing can still be recorded afterward.")
                                    .font(.caption)
                            } else {
                                Text(preparedTaskTitle).font(.title2.bold())
                                Text(preparedTaskInstructions).font(.body)
                                Text("Keep the phone in the same position. Take your time reading; recording starts only when you tap below.")
                                    .font(.subheadline)
                                Button("I'm ready — start") { viewModel.beginPreparedTask() }
                                    .buttonStyle(.borderedProminent)
                                    .tint(NeuroPulseColor.pantoneYellow)
                                    .foregroundStyle(NeuroPulseColor.pantoneBlueDark)
                            }
                        }
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(24)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(NeuroPulseColor.pantoneBlueDark)
                }

                // Camera geometry stays fixed; guidance is an overlay, not a layout shift.
                if showsTrackingWarnings, !viewModel.awaitingTaskStart, !viewModel.isRecoveringTracking, let prompt = viewModel.cameraPrompt {
                    VStack {
                        Text(prompt)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(NeuroPulseColor.pantoneYellow)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                            .background(NeuroPulseColor.pantoneBlue.opacity(0.84), in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(NeuroPulseColor.pantoneYellow.opacity(0.65), lineWidth: 1))
                            .padding(.horizontal, 14)
                            .padding(.top, 14)
                        Spacer()
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: viewModel.cameraPrompt)
            .onAppear {
                viewModel.canvasSize = geometry.size
            }
            .onChange(of: geometry.size) { _, newSize in
                viewModel.canvasSize = newSize
            }
        }
    }

    private var preparedTaskTitle: String {
        if case .lateralHold(let side, _) = viewModel.currentPhase {
            return "Hold your gaze to the \(side.rawValue.lowercased())"
        }
        return "Follow the moving dot"
    }

    private var preparedTaskInstructions: String {
        if case .lateralHold = viewModel.currentPhase {
            return "Look at the stationary side dot until the task ends. Keep your head still and move only your eyes. Blink normally."
        }
        return "After the countdown, follow the moving dot with your eyes. Keep your head still and blink normally."
    }

    // MARK: - Stage 1: Alignment Phase View
    private func alignmentPhaseView(size: CGSize) -> some View {
        VStack(spacing: 16) {
            Spacer()

            ZStack {
                OcularReticleView(
                    gazeMetrics: viewModel.tracker.currentMetrics,
                    faceDistanceCm: viewModel.tracker.faceDistanceCm,
                    isDistanceOptimal: viewModel.tracker.isDistanceOptimal,
                    isFaceDetected: viewModel.tracker.isFaceDetected,
                    reticleSize: min(size.width * 0.65, 250)
                )

                Circle()
                    .trim(from: 0, to: viewModel.calibrationHoldProgress)
                    .stroke(Color(hex: "FCEEA8"), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: min(size.width * 0.65, 250) + 16, height: min(size.width * 0.65, 250) + 16)
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .linear(duration: 0.05), value: viewModel.calibrationHoldProgress)
            }

            Spacer()


        }
        .padding(.vertical, 10)
    }

    // MARK: - Guided Calibration Phase View
    private func calibrationPhaseView(size: CGSize, activeIndex: Int) -> some View {
        ZStack {
            VStack {
                Spacer()
            }

            ForEach(viewModel.calibrationPoints.filter { $0.id == activeIndex }) { point in
                let targetPos = CGPoint(
                    x: point.screenPosition.x * size.width,
                    y: point.screenPosition.y * size.height
                )
                calibrationDotView
                    .position(targetPos)
            }

        }
    }

    /// A static bullseye stays distinct from both bright camera video and the blue field.
    private var neonTarget: some View {
        ZStack {
            Circle().fill(NeuroPulseColor.pantoneBlue).frame(width: 46, height: 46)
            Circle().fill(targetColor).frame(width: 36, height: 36)
                .shadow(color: targetColor.opacity(0.85), radius: 7)
            Circle().fill(NeuroPulseColor.pantoneBlue).frame(width: 14, height: 14)
            Circle().fill(targetColor).frame(width: 6, height: 6)
        }
        .accessibilityLabel("Bright bullseye target. Look at its center.")
    }

    private var calibrationDotView: some View {
        ZStack {
            Circle().stroke(NeuroPulseColor.pantoneBlue, lineWidth: 7)
                .frame(width: 62, height: 62)
            Circle().stroke(targetColor.opacity(0.35), lineWidth: 4)
                .frame(width: 62, height: 62)
            Circle().trim(from: 0, to: viewModel.calibrationHoldProgress)
                .stroke(targetColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 62, height: 62)
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .linear(duration: 0.05), value: viewModel.calibrationHoldProgress)
            neonTarget
        }
    }

    // MARK: - Countdown Phase View
    private func countdownPhaseView(count: Int) -> some View {
        VStack(spacing: 8) {
            Text("\(count)")
                .font(.system(size: 80, weight: .black, design: .rounded))
                .foregroundColor(NeuroPulseColor.pantoneYellow)
                .shadow(color: NeuroPulseColor.trackingAccent.opacity(0.6), radius: 16)
                .scaleEffect(reduceMotion ? 1.0 : 1.1)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: count)

            Text("FOLLOW THE MOVING DOT")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(NeuroPulseColor.cardWhite)
                .tracking(1.0)
        }
    }

    // MARK: - Stage 4: Smooth Pursuit Canvas View
    private func stimulusCanvasView(size: CGSize) -> some View {
        let stimPos = CGPoint(
            x: viewModel.stimulusTarget.x * size.width,
            y: viewModel.stimulusTarget.y * size.height
        )

        return ZStack {
            // Horizontal Guidance Axis
            Rectangle()
                .fill(NeuroPulseColor.pantoneYellow.opacity(0.12))
                .frame(width: size.width * 0.88, height: 2)
                .position(x: size.width * 0.5, y: size.height * 0.5)

            // High-Contrast Stimulus Target
            neonTarget
                .position(stimPos)


        }
    }

    // MARK: - Stage 5: Lateral Hold Canvas View
    private func lateralHoldCanvasView(size: CGSize, side: HoldSide) -> some View {
        let stimPos = CGPoint(
            x: viewModel.stimulusTarget.x * size.width,
            y: viewModel.stimulusTarget.y * size.height
        )

        return ZStack {
            neonTarget
                .position(stimPos)


        }
    }

    // MARK: - Invalid Phase View: "Recording couldn't finish"
    private func invalidPhaseView(reason: String) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(NeuroPulseColor.pantoneYellow)

                Text("Recording couldn't finish")
                    .font(.title2.bold())
                    .foregroundColor(NeuroPulseColor.pantoneYellow)

                Text(reason)
                    .font(.body)
                    .foregroundColor(NeuroPulseColor.pantoneYellow.opacity(0.88))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                VStack(spacing: 12) {
                    Button(action: onDismiss) {
                        Text("Back to Test")
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(NeuroPulseColor.pantoneYellow.opacity(0.20))
                            .foregroundColor(NeuroPulseColor.pantoneYellow)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .accessibilityLabel("Back to Test")

                    Button(action: { viewModel.startExam() }) {
                        Text("Try Again")
                            .font(.headline)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(NeuroPulseColor.pantoneYellow)
                            .foregroundColor(NeuroPulseColor.pantoneBlueDark)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .accessibilityLabel("Try Again")
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

}
