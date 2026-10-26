import SwiftUI
import CoreMotion
import AVFoundation
#if os(iOS)
import UIKit
#endif

/// Native iPhone version of PupilCheck's Tests 3 & 4. Measurements stay experimental and separate from eye-test interpretation.
public struct MotorTestsView: View {
    public let athlete: AthleteProfile
    public let eyeResult: SCAT6TriageResult
    public let onDone: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var capture = MotorCaptureState()
    @State private var reactionTimes: [Double] = []
    @State private var earlyTaps = 0
    @State private var missedTrials = 0
    @State private var attempt = 0
    @State private var cueVisible = false
    @State private var cueAt: Double?
    @State private var responseAt: Double?
    @State private var cadenceStarted: Double?
    @State private var taps: [MotorTap] = []
    @State private var multiTouchDetected = false
    @State private var lastDisplayTick: Double?
    @State private var maxDisplayGap = 0.0
    @State private var secondsRemaining = 0
    @State private var motionSamples: [MotorMotionSample] = []
    @State private var motionStart: Double?
    @State private var reactionResult: MotorMeasurement?
    @State private var balanceResult: MotorMeasurement?
    @State private var pendingSession: MotorTestSession?
    @State private var tonePlayer: AVAudioPlayer?
    @State private var ownsAudioSession = false
    @State private var helperPresent = false
    @State private var safeStance = false
    @State private var errorMessage: String?
    #if os(iOS)
    @State private var motionManager = CMMotionManager()
    #endif
    @State private var runTask: Task<Void, Never>?

    public init(athlete: AthleteProfile, eyeResult: SCAT6TriageResult, onDone: @escaping () -> Void) {
        self.athlete = athlete; self.eyeResult = eyeResult; self.onDone = onDone
    }

    public var body: some View {
        ZStack {
            if capture.stage == .results {
                ResultsView(result: eyeResult, onDone: saveAndClose, motorSession: draftSession,
                    doneTitle: "Save to player", onClose: onDone, isUnsavedMotorReview: true)
            } else {
                NeuroPulseColor.pantoneBlueDark.ignoresSafeArea()
                VStack(spacing: 18) {
                    header
                    ScrollView { content.padding(.horizontal, 22).padding(.bottom, 24) }
                }
            }
        }
        .preferredColorScheme(capture.stage == .results ? .light : .dark)
        .onChange(of: capture.stage) { _, stage in
            if stage == .results { pendingSession = makeSession() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { interruptCapture("App became inactive. Repeat the interrupted test.") }
        }
        .onDisappear {
            stopMotion(); runTask?.cancel(); capture.resetSound(); stopTone()
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
            if let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
               type == AVAudioSession.InterruptionType.began.rawValue {
                interruptCapture("Audio was interrupted. Repeat the sound check before restarting.")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
            if let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
               reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue || reason == AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue {
                interruptCapture("Audio output changed. Repeat the sound check before restarting.")
            }
        }
        #endif
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("TESTS 3 & 4").font(.system(.caption, design: .rounded).weight(.bold)).tracking(1.2).foregroundStyle(NeuroPulseColor.trackingAccent)
                Text(athlete.name).font(.system(.headline, design: .rounded).weight(.bold)).fixedSize(horizontal: false, vertical: true).foregroundStyle(NeuroPulseColor.pantoneYellow)
            }
            Spacer()
            Button(action: onDone) {
                Text("Close")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(NeuroPulseColor.pantoneYellow.opacity(0.8))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22).padding(.top, 12)
    }

    @ViewBuilder private var content: some View {
        switch capture.stage {
        case .intro: intro
        case .reaction: reaction
        case .cadenceSetup: cadenceSetup
        case .cadence: cadence
        case .balanceSetup: balanceSetup
        case .eyesOpen: balancePrompt(closed: false)
        case .eyesClosed: balancePrompt(closed: true)
        case .results: EmptyView()
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Reaction & standing motion").font(.system(.title, design: .rounded).weight(.bold)).fixedSize(horizontal: false, vertical: true).foregroundStyle(NeuroPulseColor.pantoneYellow)
            Text("For **\(athlete.name)** · about 1 minute").foregroundStyle(NeuroPulseColor.pantoneYellow.opacity(0.72))
            infoCard("3 · Reaction and tapping", "Rest the phone on a table. Use one index finger to tap only when the target lights up. There are five valid trials with unpredictable waits of 0.8–4.5 seconds. Early taps are counted and repeated. Then use that same finger to alternate between two pads.")
            infoCard("4 · Phone-motion recording", "A helper stays beside the athlete. The phone is held against the chest while standing feet together. A sensor records phone movement for 10 seconds with eyes closed.")
            infoCard("Safety", "This does not detect a concussion, measure body sway, replace SCAT6 balance testing, or clear anyone to play. Stop if standing feels unsafe.")
            if let errorMessage {
                errorNotice(errorMessage)
            }
            Button { startReactionTest() } label: { label("Start Test 3", icon: "bolt.fill") }
                .buttonStyle(.plain)
        }
    }

    private var reaction: some View {
        VStack(spacing: 20) {
            Text("REACTION · \(min(reactionTimes.count + 1, 5)) OF 5").font(.system(size: 13, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(NeuroPulseColor.trackingAccent)
            Text(cueVisible ? "TAP NOW" : "Wait for the glow").font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(NeuroPulseColor.pantoneYellow)
            Button {
                let now = ProcessInfo.processInfo.systemUptime
                if cueVisible { responseAt = now }
                else if attempt > 0 && responseAt == nil { responseAt = -now }
            } label: {
                Circle().fill(cueVisible ? NeuroPulseColor.trackingAccent : NeuroPulseColor.pantoneYellow.opacity(0.12))
                    .frame(width: 188, height: 188)
                    .overlay(Circle().stroke(NeuroPulseColor.trackingAccent.opacity(cueVisible ? 1 : 0.5), lineWidth: 3))
                    .shadow(color: NeuroPulseColor.trackingAccent.opacity(cueVisible ? 0.8 : 0), radius: 28)
                    .overlay(Image(systemName: "circle.fill").font(.system(size: 18)).foregroundStyle(cueVisible ? NeuroPulseColor.pantoneBlueDark : NeuroPulseColor.pantoneYellow.opacity(0.25)))
            }.buttonStyle(.plain).accessibilityLabel(cueVisible ? "Tap now" : "Waiting for target")
            Text("Trials so far: \(reactionTimes.count) valid · \(earlyTaps) early · \(missedTrials) missed").font(.system(size: 14)).foregroundStyle(NeuroPulseColor.pantoneYellow.opacity(0.72))
        }.frame(maxWidth: .infinity).padding(.top, 30)
    }

    private var cadenceSetup: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Next: alternating taps").font(.title.bold()).foregroundStyle(NeuroPulseColor.pantoneYellow)
            infoCard("Use one finger", "Keep the phone flat on the table. Use the same index finger to tap LEFT, RIGHT, LEFT, RIGHT as quickly and accurately as you can. Lift your finger between taps; do not use two fingers at once.")
            infoCard("What it records", "For five seconds, we record switching speed, typical time between alternating taps, and repeated taps on the same side. This describes movement speed and consistency on this phone. Practice, fatigue, hand choice, and screen layout can affect it. It is not a concussion score.")
            Button { capture.stage = .cadence; beginCadence() } label: {
                label("Start 5-second tapping", icon: "hand.tap")
            }.buttonStyle(.plain)
        }
    }

    private var cadence: some View {
        VStack(spacing: 20) {
            Text("ALTERNATING TAPS · 5 SECONDS").font(.system(size: 13, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(NeuroPulseColor.trackingAccent)
            Text("One finger: left, right, left, right").font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(NeuroPulseColor.pantoneYellow)
            #if os(iOS)
            ZStack {
                HStack(spacing: 12) { tapPadFace("LEFT"); tapPadFace("RIGHT") }
                CadenceTouchCapture(onTap: registerTap, onMultiTouch: { multiTouchDetected = true })
            }
            .frame(height: 230)
            #else
            HStack(spacing: 12) { tapPad("LEFT", side: 0); tapPad("RIGHT", side: 1) }.frame(height: 230)
            #endif
            Text("\(secondsRemaining) seconds · \(taps.count) taps")
                .font(.system(size: 15, weight: .medium, design: .rounded)).foregroundStyle(NeuroPulseColor.pantoneYellow.opacity(0.7))
        }.padding(.top, 24)
    }

    private var balanceSetup: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("4 · Standing motion").font(.system(.title, design: .rounded).weight(.bold)).foregroundStyle(NeuroPulseColor.pantoneYellow)
            infoCard("1 · Position the athlete", "Stand on a clear, level floor with feet together and eyes open. Wear the same footwear for repeat recordings. A helper must stay within arm’s reach. If dizzy, uncomfortable, or unsteady, skip this test.")
            infoCard("2 · Position the phone", "Keep the phone upright, top edge up, with its back flat against the center of the athlete's chest and the screen facing outward. The helper holds it gently in place without bracing or supporting the athlete. Do not hold it out in front or change grip during recording. The helper's movement can affect the result.")
            infoCard("3 · Listen for the tones", "Play the test tone in this position. After Start, keep eyes open through the three-second countdown. Close them at the first tone. Stay still through the one-second settling pause and ten-second recording. Open eyes at the ending tone. The helper can tap Stop at any time; stop immediately if the athlete loses balance.")
            infoCard("What the numbers mean", "The phone records acceleration and changes in tilt. Larger values mean more phone movement during this attempt. They can also reflect the helper's grip or phone placement. This does not measure force-plate sway, count balance errors, or provide a concussion diagnosis.")
            Toggle("A helper is beside the athlete", isOn: $helperPresent).tint(NeuroPulseColor.trackingAccent)
            Toggle("The athlete feels safe standing this way", isOn: $safeStance).tint(NeuroPulseColor.trackingAccent)
            Button { capture.resetSound(); capture.tonePlayed = playTone() } label: {
                label("Play test tone", icon: "speaker.wave.2.fill")
            }.buttonStyle(.plain)
            Toggle("The athlete heard the tone", isOn: $capture.heardTone)
                .disabled(!capture.tonePlayed).tint(NeuroPulseColor.trackingAccent)
            Text("Keep the phone against the chest for this check. Confirm only if the athlete hears the tone. Turn up media volume and disconnect headphones or Bluetooth to use the phone speaker. If the cue is not audible, skip Test 4.")
                .font(.system(size: 14)).foregroundStyle(NeuroPulseColor.pantoneYellow.opacity(0.75))
            Text("Keep eyes open during the countdown. At the start tone, close your eyes and stay still. Open them at the ending tone. A short settling pause allows the athlete to settle before recording.")
                .font(.system(size: 14)).foregroundStyle(NeuroPulseColor.pantoneYellow.opacity(0.75))
            if let errorMessage { errorNotice(errorMessage) }
            Button {
                guard motionAvailable else { errorMessage = "This device does not provide the required motion sensor."; return }
                guard helperPresent && safeStance && capture.soundConfirmed else { errorMessage = "Confirm a nearby helper, a safe stance, and that the tone is heard."; return }
                runTask = Task { await runBalance() }
            } label: { label("Start supervised recording", icon: "figure.stand") }.buttonStyle(.plain)
            Button {
                balanceResult = MotorMeasurement(status: "skipped", reason: "Skipped by coach.")
                capture.stage = .results
            } label: {
                Text("Skip Test 4")
                    .font(.body.weight(.medium))
                    .foregroundStyle(NeuroPulseColor.pantoneYellow.opacity(0.85))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func balancePrompt(closed: Bool) -> some View {
        VStack(spacing: 20) {
            Text(closed ? "EYES CLOSED" : "EYES OPEN").font(.system(size: 14, weight: .bold, design: .rounded)).tracking(1.2).foregroundStyle(NeuroPulseColor.trackingAccent)
            Text(closed ? "Keep still. Keep the phone against the chest." : "Stand ready with feet together.").font(.system(size: 23, weight: .bold, design: .rounded)).foregroundStyle(NeuroPulseColor.pantoneYellow).multilineTextAlignment(.center)
            Text("\(secondsRemaining)")
                .font(.system(size: 72, weight: .light, design: .rounded).monospacedDigit()).foregroundStyle(NeuroPulseColor.pantoneYellow)
            Button("Stop recording") { runTask?.cancel(); stopMotion(); balanceResult = MotorMeasurement(status: "interrupted", reason: "Stopped before the full 10 seconds."); capture.stage = .results }
                .foregroundStyle(NeuroPulseColor.pantoneYellow.opacity(0.8)).padding()
        }.frame(maxWidth: .infinity).padding(.top, 55)
    }

    private func tapPad(_ title: String, side: Int) -> some View {
        Button {
            registerTap(ProcessInfo.processInfo.systemUptime, side)
        } label: {
            tapPadFace(title)
        }.buttonStyle(.plain)
    }

    private func tapPadFace(_ title: String) -> some View {
        RoundedRectangle(cornerRadius: 24).fill(NeuroPulseColor.trackingAccent.opacity(0.14))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(NeuroPulseColor.trackingAccent, lineWidth: 2))
            .overlay(Text(title).font(.system(size: 22, weight: .black, design: .rounded)).foregroundStyle(NeuroPulseColor.pantoneYellow))
    }

    private func registerTap(_ uptime: Double, _ side: Int) {
        guard let start = cadenceStarted else { return }
        let elapsed = uptime - start
        guard elapsed >= 0, elapsed <= 5 else { return }
        taps.append(MotorTap(t: elapsed, side: side))
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    private func errorNotice(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(NeuroPulseColor.cardWhite)
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NeuroPulseColor.pantoneRed, in: RoundedRectangle(cornerRadius: 12))
    }

    private func infoCard(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(.headline, design: .rounded).weight(.bold)).foregroundStyle(NeuroPulseColor.trackingAccent)
            Text(text).font(.subheadline).foregroundStyle(NeuroPulseColor.cardWhite.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(NeuroPulseColor.pantoneYellow.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func label(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).font(.system(.headline, design: .rounded).weight(.bold))
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(NeuroPulseColor.pantoneBlueDark).padding(.vertical, 16).frame(maxWidth: .infinity)
            .background(NeuroPulseColor.trackingAccent).clipShape(RoundedRectangle(cornerRadius: 15))
    }

    private func startReactionTest() {
        runTask?.cancel()
        reactionTimes = []; earlyTaps = 0; missedTrials = 0; attempt = 0
        cueVisible = false; cueAt = nil; responseAt = nil; cadenceStarted = nil
        taps = []; multiTouchDetected = false; reactionResult = nil; errorMessage = nil
        capture.stage = .reaction
        runTask = Task { await runReactions() }
    }

    private func interruptCapture(_ reason: String) {
        let interrupted = capture.interrupt()
        runTask?.cancel(); stopMotion(); stopTone()
        cueVisible = false; responseAt = nil; cadenceStarted = nil
        switch interrupted {
        case .reaction:
            reactionTimes = []; taps = []
            reactionResult = MotorMeasurement(status: "interrupted", reason: reason)
            errorMessage = reason
        case .balance:
            motionSamples = []
            balanceResult = MotorMeasurement(status: "interrupted", reason: reason)
            errorMessage = "Open your eyes. \(reason) Repeat the sound check before starting again."
        case nil:
            if capture.stage == .balanceSetup { errorMessage = "Repeat the sound check before starting." }
        }
    }

    private func runReactions() async {
        maxDisplayGap = 0
        lastDisplayTick = ProcessInfo.processInfo.systemUptime
        var attempts = 0
        while reactionTimes.count < 5 && attempts < 15 && !Task.isCancelled {
            attempts += 1; attempt = attempts; responseAt = nil; cueVisible = false
            await waitAndMeasureDisplay(for: .milliseconds(Int.random(in: 800...4500)))
            guard !Task.isCancelled else { return }
            let shown = ProcessInfo.processInfo.systemUptime; cueAt = shown; cueVisible = true
            let deadline = shown + 3
            while responseAt == nil && ProcessInfo.processInfo.systemUptime < deadline && !Task.isCancelled {
                await waitAndMeasureDisplay(for: .milliseconds(16))
            }
            guard !Task.isCancelled else { return }
            cueVisible = false
            if let responseAt, responseAt < 0 || (responseAt >= shown && responseAt - shown < 0.1) { earlyTaps += 1 }
            else if let responseAt, responseAt >= shown, responseAt - shown <= 3 { reactionTimes.append(responseAt - shown) }
            else { missedTrials += 1 }
        }
        guard !Task.isCancelled else { return }
        reactionResult = reactionTimes.count == 5
            ? MotorTestAnalysis.reaction(times: reactionTimes, early: earlyTaps, missed: missedTrials, taps: [], duration: 0, maxFrameGap: 0)
            : MotorMeasurement(status: "insufficient_quality", reason: "Need five valid reaction trials within fifteen attempts; recorded \(reactionTimes.count).")
        // Reaction timings are retained even before the separate cadence check.
        if reactionTimes.count == 5 { capture.stage = .cadenceSetup }
        else { capture.stage = .balanceSetup }
    }

    private func beginCadence() {
        taps = []; multiTouchDetected = false
        let start = ProcessInfo.processInfo.systemUptime; cadenceStarted = start
        runTask = Task {
            var last = start
            while ProcessInfo.processInfo.systemUptime - start < 5 && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard !Task.isCancelled else { return }
                let now = ProcessInfo.processInfo.systemUptime
                maxDisplayGap = max(maxDisplayGap, now - last); last = now
                secondsRemaining = max(0, 5 - Int(now - start))
            }
            guard !Task.isCancelled else { return }
            reactionResult = MotorTestAnalysis.reaction(times: reactionTimes, early: earlyTaps, missed: missedTrials, taps: taps, duration: ProcessInfo.processInfo.systemUptime - start, maxFrameGap: maxDisplayGap, multiTouch: multiTouchDetected)
            capture.stage = .balanceSetup
        }
    }

    private func runBalance() async {
        guard !Task.isCancelled else { return }
        #if os(iOS)
        motionSamples = []; errorMessage = nil; capture.stage = .eyesOpen
        for remaining in stride(from: 3, through: 1, by: -1) {
            guard !Task.isCancelled else { return }
            secondsRemaining = remaining
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
        }
        guard !Task.isCancelled else { return }
        guard playTone() else {
            capture.resetSound(); capture.stage = .balanceSetup
            return
        }
        capture.stage = .eyesClosed
        secondsRemaining = 11
        // Warm up the sensor during the existing settling pause; retain only the
        // following ten-second window, after the tone has finished.
        let start = ProcessInfo.processInfo.systemUptime + 1
        let deadline = start + 10
        motionStart = start
        motionManager.deviceMotionUpdateInterval = 1.0 / 50.0
        motionManager.startDeviceMotionUpdates(to: .main) { motion, _ in
            guard self.capture.stage == .eyesClosed, self.motionStart == start, let motion else { return }
            let elapsed = motion.timestamp - start
            guard elapsed >= 0, elapsed <= 10 else { return }
            let a = motion.userAcceleration
            let g = motion.gravity
            let r = motion.rotationRate
            self.motionSamples.append(MotorMotionSample(t: elapsed,
                acceleration: (a.x * 9.80665, a.y * 9.80665, a.z * 9.80665), gravity: (g.x, g.y, g.z), rotation: (r.x, r.y, r.z)))
        }
        // Anchor to one monotonic deadline instead of accumulating ten sleep overruns.
        while ProcessInfo.processInfo.systemUptime < deadline {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            secondsRemaining = max(1, Int(ceil(remaining)))
            try? await Task.sleep(for: .milliseconds(20))
            guard !Task.isCancelled else { return }
        }
        guard !Task.isCancelled else { return }
        let duration = ProcessInfo.processInfo.systemUptime - start
        stopMotion()
        let endingTonePlayed = playTone()
        balanceResult = MotorTestAnalysis.balance(samples: motionSamples.map {
            // CoreMotion gravity is already normalized; convert its vector to the branch's m/s² scale.
            MotorMotionSample(t: $0.t, acceleration: ($0.ax, $0.ay, $0.az), gravity: ($0.gx * 9.80665, $0.gy * 9.80665, $0.gz * 9.80665), rotation: ($0.rx, $0.ry, $0.rz))
        }, duration: duration)
        if !endingTonePlayed {
            balanceResult = MotorMeasurement(status: "interrupted", reason: "The ending tone could not play. Open eyes with the helper's guidance, then repeat the sound check before another attempt.")
        }
        capture.stage = .results
        #else
        balanceResult = MotorMeasurement(status: "unavailable", reason: "Motion capture is available on iPhone and iPad only.")
        capture.stage = .results
        #endif
    }

    private var motionAvailable: Bool {
        #if os(iOS)
        return motionManager.isDeviceMotionAvailable
        #else
        return false
        #endif
    }

    private func stopMotion() {
        motionStart = nil
        #if os(iOS)
        if motionManager.isDeviceMotionActive { motionManager.stopDeviceMotionUpdates() }
        #endif
    }

    private func waitAndMeasureDisplay(for duration: Duration) async {
        let start = ProcessInfo.processInfo.systemUptime
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        while ProcessInfo.processInfo.systemUptime - start < seconds && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { return }
            let now = ProcessInfo.processInfo.systemUptime
            if let prior = lastDisplayTick { maxDisplayGap = max(maxDisplayGap, now - prior) }
            lastDisplayTick = now
        }
    }
    private func playTone() -> Bool {
        do {
            #if os(iOS)
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playback, mode: .default)
            try audio.setActive(true)
            ownsAudioSession = true
            guard audio.outputVolume > 0 else {
                errorMessage = "Sound volume is zero. Turn it up and play the test tone again."
                return false
            }
            #endif
            tonePlayer?.stop()
            let player = try AVAudioPlayer(data: MotorTestAnalysis.standingToneWAV())
            player.volume = 1
            guard player.prepareToPlay(), player.play() else {
                errorMessage = "The tone could not start. Check audio output and try the sound check again."
                return false
            }
            tonePlayer = player
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Audio could not start: \(error.localizedDescription)"
            return false
        }
    }

    private func stopTone() {
        tonePlayer?.stop(); tonePlayer = nil
        #if os(iOS)
        if ownsAudioSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            ownsAudioSession = false
        }
        #endif
    }

    private var draftSession: MotorTestSession {
        pendingSession ?? makeSession()
    }

    private func makeSession() -> MotorTestSession {
        BaselineManager.shared.motorSession(for: eyeResult,
            reaction: reactionResult ?? MotorMeasurement(status: "unavailable", reason: "No result."),
            balance: balanceResult ?? MotorMeasurement(status: "unavailable", reason: "No result."))
    }

    private func saveAndClose() {
        BaselineManager.shared.recordMotorSession(athleteId: athlete.id, session: draftSession)
        onDone()
    }

}

#if os(iOS)
private struct CadenceTouchCapture: UIViewRepresentable {
    let onTap: (Double, Int) -> Void
    let onMultiTouch: () -> Void
    func makeUIView(context: Context) -> CadenceTouchSurface {
        let view = CadenceTouchSurface()
        view.onTap = onTap; view.onMultiTouch = onMultiTouch
        return view
    }
    func updateUIView(_ view: CadenceTouchSurface, context: Context) {
        view.onTap = onTap; view.onMultiTouch = onMultiTouch
    }
}

private final class CadenceTouchSurface: UIView {
    var onTap: ((Double, Int) -> Void)?
    var onMultiTouch: (() -> Void)?
    private var activeTouches = Set<ObjectIdentifier>()
    private var invalidTouchGroup = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        if !activeTouches.isEmpty || touches.count > 1 {
            invalidTouchGroup = true
            onMultiTouch?()
        }
        touches.forEach { activeTouches.insert(ObjectIdentifier($0)) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        for touch in touches {
            let onlyFinger = activeTouches.count == 1 && !invalidTouchGroup
            let side = touch.location(in: self).x < bounds.midX ? 0 : 1
            activeTouches.remove(ObjectIdentifier(touch))
            if onlyFinger { onTap?(ProcessInfo.processInfo.systemUptime, side) }
        }
        if activeTouches.isEmpty { invalidTouchGroup = false }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        onMultiTouch?()
        activeTouches.subtract(touches.map(ObjectIdentifier.init))
        invalidTouchGroup = true
        if activeTouches.isEmpty { invalidTouchGroup = false }
        super.touchesCancelled(touches, with: event)
    }
}
#endif
