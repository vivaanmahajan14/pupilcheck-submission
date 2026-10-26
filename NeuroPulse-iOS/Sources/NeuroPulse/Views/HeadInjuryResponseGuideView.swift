import SwiftUI

/// Authoritative Sideline Head Injury Response Guide & CRT6 (Concussion Recognition Tool 6).
/// Designed for coaches, parents, and athletic staff following the 6th International Consensus
/// on Concussion in Sport (Amsterdam 2022). Emphasizes 'Recognize and Remove'.
public struct HeadInjuryResponseGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    // Interactive Maddocks questions state
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var checkedMaddocks: Set<Int> = []

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                NeuroPulseColor.pantoneYellowCanvas
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // 1. URGENT RED FLAGS BANNER (Reserved Red for Emergency)
                        emergencyRedFlagsCard

                        // 2. IMMEDIATE ACTION: RECOGNIZE & REMOVE
                        recognizeAndRemoveCard

                        // 3. CRT6 OBSERVABLE SIGNS
                        observableSignsCard

                        // 4. CRT6 REPORTED SYMPTOMS
                        reportedSymptomsCard

                        // 5. ON-FIELD MADDOCKS MEMORY QUESTIONS
                        maddocksQuestionsCard

                        // 6. CLINICAL & REGULATORY DISCLAIMER
                        disclaimerCard
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Head Injury Response Guide")
            .navigationInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Text("Done")
                            .fixedSize(horizontal: false, vertical: true)
                            .font(.body.weight(.bold))
                            .foregroundColor(NeuroPulseColor.pantoneBlue)
                    }
                }
            }
        }
        .preferredColorScheme(.light)
        .buttonStyle(.plain)
    }

    // MARK: - 1. Emergency Red Flags
    private var emergencyRedFlagsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.system(size: 22, weight: .black))
                    .foregroundColor(NeuroPulseColor.cardWhite)

                VStack(alignment: .leading, spacing: 2) {
                    Text("STEP 1: EMERGENCY RED FLAGS")
                        .fixedSize(horizontal: false, vertical: true)
                        .font(.system(.caption, design: .monospaced).weight(.black))
                        .foregroundColor(NeuroPulseColor.pantoneYellow)

                    Text("Call 911 / EMS Immediately")
                        .fixedSize(horizontal: false, vertical: true)
                        .font(.headline.weight(.black))
                        .foregroundColor(NeuroPulseColor.cardWhite)
                }

                Spacer()
            }

            Text("If ANY of these signs are present after a suspected head impact, immediately activate emergency medical services and transport to an emergency department:")
                .fixedSize(horizontal: false, vertical: true)
                .font(.subheadline.weight(.medium))
                .foregroundColor(NeuroPulseColor.cardWhite.opacity(0.95))
                .lineSpacing(2)

            VStack(alignment: .leading, spacing: 7) {
                redFlagItem("Neck pain or neck tenderness")
                redFlagItem("Double vision")
                redFlagItem("Weakness, tingling, or burning in arms or legs")
                redFlagItem("Severe or increasing headache")
                redFlagItem("Seizure, fits, or convulsion")
                redFlagItem("Loss of consciousness (even briefly)")
                redFlagItem("Deteriorating conscious state or drowsiness")
                redFlagItem("Repeated vomiting")
                redFlagItem("Increasingly restless, agitated, or combative")
            }
            .padding(.vertical, 4)

            // Direct Emergency Call Action
            Button(action: {
                if let url = URL(string: "tel://911") {
                    openURL(url)
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "phone.fill")
                        .font(.subheadline.weight(.bold))
                    Text("CALL EMERGENCY SERVICES (911)")
                        .fixedSize(horizontal: false, vertical: true)
                        .font(.subheadline.weight(.black))
                        .tracking(0.5)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.vertical, 12)
                .background(NeuroPulseColor.pantoneBlueDark)
                .foregroundColor(NeuroPulseColor.pantoneYellow)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.top, 4)
        }
        .padding(18)
        .background(NeuroPulseColor.pantoneRed)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: NeuroPulseColor.pantoneRed.opacity(0.35), radius: 12, y: 4)
    }

    private func redFlagItem(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "xmark.circle.fill")
                .font(.subheadline.weight(.bold))
                .foregroundColor(NeuroPulseColor.pantoneYellow)
                .padding(.top, 2)

            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .font(.subheadline.weight(.bold))
                .foregroundColor(NeuroPulseColor.cardWhite)
        }
    }

    // MARK: - 2. Immediate Action Protocol
    private var recognizeAndRemoveCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fill")
                    .font(.title3.weight(.bold))
                    .foregroundColor(NeuroPulseColor.pantoneBlue)

                Text("CORE PRINCIPLE: RECOGNIZE & REMOVE")
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.system(.footnote, design: .monospaced).weight(.black))
                    .foregroundColor(NeuroPulseColor.pantoneBlue)
            }

            Text("\"If in doubt, sit them out.\"")
                .fixedSize(horizontal: false, vertical: true)
                .font(.title3.weight(.black))
                .foregroundColor(NeuroPulseColor.pantoneBlue)

            VStack(alignment: .leading, spacing: 8) {
                protocolStep(num: "1", title: "Immediate Sideline Removal", detail: "Remove athlete immediately from play, scrimmage, or practice.")
                protocolStep(num: "2", title: "Do Not Leave Alone", detail: "A responsible adult must monitor the athlete continuously over the initial hours.")
                protocolStep(num: "3", title: "No Same-Day Return", detail: "Under NO circumstances should an athlete return to play on the day of suspected concussion.")
                protocolStep(num: "4", title: "Do Not Allow Driving", detail: "Athlete should not drive a motor vehicle until medically cleared.")
                protocolStep(num: "5", title: "Formal Medical Evaluation", detail: "Refer to a medical doctor, athletic trainer, or qualified healthcare professional.")
            }
        }
        .padding(18)
        .background(NeuroPulseColor.cardWhite)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(NeuroPulseColor.pantoneBlue.opacity(0.18), lineWidth: 1)
        )
    }

    private func protocolStep(num: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(NeuroPulseColor.pantoneBlue)
                    .frame(width: 22, height: 22)
                Text(num)
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.caption.weight(.bold))
                    .foregroundColor(NeuroPulseColor.pantoneYellow)
            }
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(NeuroPulseColor.pantoneBlue)

                Text(detail)
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.footnote)
                    .foregroundColor(NeuroPulseColor.pantoneBlue.opacity(0.70))
            }
        }
    }

    // MARK: - 3. CRT6 Observable Signs
    private var observableSignsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "eye.fill")
                    .font(.headline.weight(.bold))
                    .foregroundColor(NeuroPulseColor.pantoneBlue)

                Text("STEP 2: OBSERVABLE SIGNS")
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.system(.footnote, design: .monospaced).weight(.black))
                    .foregroundColor(NeuroPulseColor.pantoneBlue)
            }

            Text("What you or others witness on the field:")
                .fixedSize(horizontal: false, vertical: true)
                .font(.subheadline.weight(.medium))
                .foregroundColor(NeuroPulseColor.pantoneBlue.opacity(0.75))

            VStack(alignment: .leading, spacing: 6) {
                signBullet("Lying motionless on the playing surface")
                signBullet("Slow to get up after a direct or indirect hit to the head")
                signBullet("Disorientation, vacant stare, or inability to respond to questions")
                signBullet("Balance difficulties, motor incoordination, stumbling, or wobbling")
                signBullet("Grabbing or clutching the head")
                signBullet("Facial injury or bleeding following head trauma")
            }
        }
        .padding(18)
        .background(NeuroPulseColor.cardWhite)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(NeuroPulseColor.pantoneBlue.opacity(0.18), lineWidth: 1)
        )
    }

    private func signBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(NeuroPulseColor.pantoneBlue)
                .frame(width: 5, height: 5)
                .padding(.top, 6)

            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(NeuroPulseColor.pantoneBlue)
        }
    }

    // MARK: - 4. CRT6 Reported Symptoms
    private var reportedSymptomsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .font(.headline.weight(.bold))
                    .foregroundColor(NeuroPulseColor.pantoneBlue)

                Text("STEP 3: REPORTED SYMPTOMS")
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.system(.footnote, design: .monospaced).weight(.black))
                    .foregroundColor(NeuroPulseColor.pantoneBlue)
            }

            Text("What the athlete states they feel:")
                .fixedSize(horizontal: false, vertical: true)
                .font(.subheadline.weight(.medium))
                .foregroundColor(NeuroPulseColor.pantoneBlue.opacity(0.75))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: textSize.isAccessibilitySize ? 260 : 130), alignment: .leading)], alignment: .leading, spacing: 8) {
                symptomPill("Headache / Pressure")
                symptomPill("Dizziness")
                symptomPill("Blurred Vision")
                symptomPill("Light Sensitivity")
                symptomPill("Noise Sensitivity")
                symptomPill("Nausea")
                symptomPill("Feeling Foggy")
                symptomPill("Difficulty Thinking")
                symptomPill("Fatigue / Low Energy")
                symptomPill("Neck Discomfort")
            }
        }
        .padding(18)
        .background(NeuroPulseColor.cardWhite)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(NeuroPulseColor.pantoneBlue.opacity(0.18), lineWidth: 1)
        )
    }

    private func symptomPill(_ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundColor(NeuroPulseColor.pantoneBlue.opacity(0.5))

            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .font(.footnote.weight(.medium))
                .foregroundColor(NeuroPulseColor.pantoneBlue)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NeuroPulseColor.pantoneYellowCanvas)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - 5. Maddocks Memory Questions
    private var maddocksQuestionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.headline.weight(.bold))
                    .foregroundColor(NeuroPulseColor.pantoneBlue)

                Text("STEP 4: ON-FIELD MADDOCKS QUESTIONS")
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.system(.footnote, design: .monospaced).weight(.black))
                    .foregroundColor(NeuroPulseColor.pantoneBlue)
            }

            Text("Ask the athlete these 5 standard orientation questions. An incorrect answer strongly suggests a concussion:")
                .fixedSize(horizontal: false, vertical: true)
                .font(.subheadline)
                .foregroundColor(NeuroPulseColor.pantoneBlue.opacity(0.75))
                .lineSpacing(2)

            let questions = [
                "\"Where are we today / what venue are we at?\"",
                "\"Which half or period is it right now?\"",
                "\"Who scored last in this game / match?\"",
                "\"What team did you play in your last match?\"",
                "\"Did your team win the last match?\""
            ]

            VStack(spacing: 8) {
                ForEach(0..<questions.count, id: \.self) { idx in
                    let isChecked = checkedMaddocks.contains(idx)
                    Button(action: {
                        if isChecked {
                            checkedMaddocks.remove(idx)
                        } else {
                            checkedMaddocks.insert(idx)
                        }
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                                .font(.title3)
                                .foregroundColor(NeuroPulseColor.pantoneBlue)

                            Text(questions[idx])
                                .fixedSize(horizontal: false, vertical: true)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(NeuroPulseColor.pantoneBlue)
                                .multilineTextAlignment(.leading)

                            Spacer()
                        }
                        .padding(10)
                        .background(isChecked ? Color(hex: "FCEEA8").opacity(0.12) : NeuroPulseColor.pantoneYellowCanvas)
                        .frame(minHeight: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(isChecked ? "Marked correct" : "Not marked")
                    .accessibilityHint("Toggle whether this question was answered correctly")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Answered correctly: \(checkedMaddocks.count)/5")
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.system(.footnote, design: .monospaced).weight(.bold))
                    .foregroundColor(NeuroPulseColor.pantoneBlue)

                if checkedMaddocks.count < 5 && !checkedMaddocks.isEmpty {
                    Text("Deficit Indicated")
                        .fixedSize(horizontal: false, vertical: true)
                        .font(.caption.weight(.bold))
                        .foregroundColor(NeuroPulseColor.pantoneRed)
                }
            }
            .padding(.top, 4)
        }
        .padding(18)
        .background(NeuroPulseColor.cardWhite)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(NeuroPulseColor.pantoneBlue.opacity(0.18), lineWidth: 1)
        )
    }

    // MARK: - 6. Educational & Clinical Disclaimer
    private var disclaimerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.subheadline)
                    .foregroundColor(NeuroPulseColor.pantoneBlue)

                Text("EDUCATIONAL & SIDELINE PROTOCOL NOTICE")
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .foregroundColor(NeuroPulseColor.pantoneBlue)
            }

            Text("This response guide is based on the Consensus Statement on Concussion in Sport (Amsterdam 2022) CRT6. It is designed for non-medical personnel to aid recognition. It does not replace clinical judgment or a formal SCAT6 examination conducted by a licensed medical practitioner. NeuroPulse's experimental ARKit eye-tracking recorder is an exploratory demonstration and does NOT diagnose concussions or provide return-to-play clearance.")
                .fixedSize(horizontal: false, vertical: true)
                .font(.caption)
                .foregroundColor(NeuroPulseColor.pantoneBlue.opacity(0.70))
                .lineSpacing(2)
        }
        .padding(14)
        .background(NeuroPulseColor.pantoneBlue.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
