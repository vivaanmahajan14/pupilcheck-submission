import SwiftUI

/// Coach home: choose a player, choose a recording, then start the live AR session.
public struct DashboardView: View {
    @StateObject private var baselineManager = BaselineManager.shared
    @StateObject private var tracker = ARFaceGazeTracker()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedAthleteId: String?
    @State private var selectedTab = 0
    @State private var mode: RecordingMode = .session
    @State private var showingPlayerPicker = false
    @State private var showingExam = false
    @State private var showingMotorTests = false
    @State private var eyeResultForMotorTests: SCAT6TriageResult?
    @State private var showingInjuryGuide = false
    @State private var showingBaselineReplacement = false
    @State private var selectedResult: SCAT6TriageResult?

    public init() {}

    public var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                testHome
            }
            .tabItem { Label("Test", systemImage: "viewfinder") }
            .tag(0)

            NavigationStack {
                AthleteRosterView(baselineManager: baselineManager) { athlete in
                    selectedAthleteId = athlete.id
                    mode = .baseline
                    withAnimation(animation) { selectedTab = 0 }
                }
            }
            .tabItem { Label("Teams", systemImage: "person.3") }
            .tag(1)
        }
        .tint(NeuroPulseColor.pantoneBlue)
        .preferredColorScheme(.light)
        .sheet(isPresented: $showingPlayerPicker) {
            PlayerPickerView(
                baselineManager: baselineManager,
                selectedAthleteId: $selectedAthleteId
            )
        }
        .sheet(isPresented: $showingInjuryGuide) {
            HeadInjuryResponseGuideView()
        }
        .sheet(item: $selectedResult) { result in
            ResultsView(result: result) { selectedResult = nil }
        }
        .confirmationDialog(
            "Replace \(currentAthlete?.name ?? "this player's") baseline?",
            isPresented: $showingBaselineReplacement,
            titleVisibility: .visible
        ) {
            Button("Replace baseline", role: .destructive) { beginRecording() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The saved reference changes only after the new recording finishes successfully.")
        }
        .examPresentationCover(isPresented: $showingExam) {
            if let athlete = currentAthlete {
                GazeExamView(
                    athlete: athlete,
                    isBaselineMode: mode == .baseline,
                    tracker: tracker,
                    onDismiss: { showingExam = false },
                    onContinueToMotorTests: { result in
                        eyeResultForMotorTests = result
                        showingExam = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showingMotorTests = true }
                    }
                )
            }
        }
        .examPresentationCover(isPresented: $showingMotorTests) {
            if let athlete = currentAthlete, let result = eyeResultForMotorTests {
                MotorTestsView(athlete: athlete, eyeResult: result) { showingMotorTests = false }
            }
        }
        .onChange(of: baselineManager.athletes.map(\.id)) { _, ids in
            if let selectedAthleteId, !ids.contains(selectedAthleteId) {
                self.selectedAthleteId = nil
            }
        }
    }

    private var testHome: some View {
        ZStack {
            NeuroPulseColor.pantoneYellowCanvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    intro
                    playerCard
                    recordingCard
                    recentRecordings
                    safetyNote
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Test")
        .navigationInlineTitle()
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { showingInjuryGuide = true } label: {
                    Label("Injury guide", systemImage: "cross.case.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(NeuroPulseColor.pantoneRed)
                }
                .accessibilityLabel("Open head injury response guide")
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NEUROPULSE")
                .font(.system(.caption, design: .rounded).weight(.heavy))
                .tracking(2)
                .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.65))

            Text("Player check-in")
                .font(.system(.title, design: .rounded).weight(.bold))
                .tracking(-0.4)
                .foregroundStyle(NeuroPulseColor.pantoneBlue)
                .fixedSize(horizontal: false, vertical: true)

            Text("Four experimental movement tests, with recordings saved to each player.")
                .font(.body)
                .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 2)
    }

    private var playerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PLAYER")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .tracking(1.1)
                .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.62))

            Button { showingPlayerPicker = true } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(NeuroPulseColor.pantoneBlueSurface)
                            .frame(width: 52, height: 52)
                        Image(systemName: currentAthlete == nil ? "person.crop.circle.badge.plus" : "person.fill")
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(NeuroPulseColor.pantoneBlue)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(currentAthlete?.name ?? "Choose a player")
                            .font(.system(.headline, design: .rounded).weight(.semibold))
                            .foregroundStyle(NeuroPulseColor.pantoneBlue)
                        Text(playerSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.68))
                    }

                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.45))
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Select which player's recording to save")
        }
        .appSurface()
        .animation(animation, value: selectedAthleteId)
    }

    private var recordingCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(mode == .baseline ? "Set a personal baseline" : "Record a test session")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(NeuroPulseColor.pantoneBlue)
                Text(mode == .baseline
                     ? "Save a reference to compare with future recordings."
                     : "Start with eye tracking, then continue to reaction and standing motion.")
                    .font(.subheadline)
                    .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.76))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker("Recording type", selection: $mode) {
                ForEach(RecordingMode.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Recording type")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: 14) {
                testStep(1, "Eye tracking")
                testStep(2, "Side gaze hold")
                testStep(3, "Reaction & taps")
                testStep(4, "Standing motion")
            }

            if currentAthlete?.baseline != nil && mode == .session {
                Label("Personal baseline available", systemImage: "bookmark.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(NeuroPulseColor.pantoneBlue)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: requestStart) {
                HStack(spacing: 8) {
                    Text(mode == .baseline ? "Start baseline" : "Start test session")
                    Image(systemName: "arrow.right")
                }
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(NeuroPulseColor.cardWhite)
                .frame(maxWidth: .infinity, minHeight: 24)
                .padding(16)
                .background(canStart ? NeuroPulseColor.pantoneBlue : NeuroPulseColor.pantoneBlue.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canStart)
            .accessibilityHint(canStart ? "Opens the live camera test" : "Choose a player first")

            if !canStart {
                Text("Choose or add a player above to continue.")
                    .font(.footnote)
                    .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.76))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .appSurface()
        .animation(animation, value: mode)
        .animation(animation, value: currentAthlete?.baseline != nil)
    }

    private func testStep(_ number: Int, _ title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.caption.weight(.bold).monospacedDigit())
                .padding(6)
                .background(NeuroPulseColor.pantoneBlueSurface, in: RoundedRectangle(cornerRadius: 7))
            Text(title)
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(NeuroPulseColor.pantoneBlue)
        .accessibilityElement(children: .combine)
    }

    private var recentRecordings: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent recordings")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(NeuroPulseColor.pantoneBlue)
                Spacer()
                if currentAthlete != nil {
                    Text("Latest")
                        .font(.caption.weight(.semibold))
                        .tracking(0.8)
                        .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.5))
                }
            }

            if let athlete = currentAthlete, !athlete.triageHistory.isEmpty {
                ForEach(athlete.triageHistory.prefix(3)) { record in
                    Button { selectedResult = record } label: {
                        RecordingSummaryRow(record: record, detail: nil, badgeColor: badgeColor(for: record))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text(currentAthlete == nil
                     ? "Choose a player to see their recordings here."
                     : "Completed recordings will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.65))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(NeuroPulseColor.cardWhite)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var safetyNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(NeuroPulseColor.pantoneBlue)
            Text("These movement tests are experimental. They cannot diagnose an injury or clear a player. For a suspected head injury, use the injury guide and seek medical care.")
                    .font(.footnote)
                .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.74))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 2)
    }

    private var currentAthlete: AthleteProfile? {
        guard let selectedAthleteId else { return nil }
        return baselineManager.getAthlete(id: selectedAthleteId)
    }

    private var canStart: Bool { currentAthlete != nil }

    private var playerSubtitle: String {
        guard let athlete = currentAthlete else { return "Required before a recording can start" }
        let team = baselineManager.teams.first(where: { $0.id == athlete.teamId })?.name
        let number = athlete.jerseyNumber.isEmpty ? nil : "#\(athlete.jerseyNumber)"
        return [team, number, athlete.baseline == nil ? "No baseline yet" : "Baseline saved"]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var animation: Animation? { reduceMotion ? nil : .snappy(duration: 0.24) }

    private func requestStart() {
        guard let athlete = currentAthlete else { return }
        if mode == .baseline, athlete.baseline != nil {
            showingBaselineReplacement = true
        } else {
            beginRecording()
        }
    }

    private func beginRecording() {
        guard currentAthlete != nil else { return }
        showingExam = true
    }

    private func badgeColor(for record: SCAT6TriageResult) -> Color {
        if record.isBaselineTest { return NeuroPulseColor.pantoneBlue }
        switch record.overallStatus {
        case .criticalAlert, .elevatedRisk: return NeuroPulseColor.statusElevated
        case .borderline: return NeuroPulseColor.statusBorderline
        case .normal, .recorded: return NeuroPulseColor.pantoneBlue
        }
    }
}

private enum RecordingMode: String, CaseIterable, Identifiable {
    case session
    case baseline

    var id: String { rawValue }
    var title: String { self == .baseline ? "Baseline" : "Session" }
}

private struct PlayerPickerView: View {
    @ObservedObject var baselineManager: BaselineManager
    @Binding var selectedAthleteId: String?
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var showingAddPlayer = false
    @State private var addedPlayer = false

    private var matchingAthletes: [AthleteProfile] {
        baselineManager.athletes
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NeuroPulseColor.pantoneYellowCanvas.ignoresSafeArea()
                List {
                    if matchingAthletes.isEmpty {
                        ContentUnavailableView {
                            Label(searchText.isEmpty ? "No players yet" : "No matching players", systemImage: "person.2")
                                .foregroundStyle(NeuroPulseColor.pantoneBlue)
                        } description: {
                            Text(searchText.isEmpty
                                 ? "Add a player to start a recording. You can organize players into teams later."
                                 : "Try another name, clear your search, or add a new player.")
                                .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.8))
                        } actions: {
                            Button { showingAddPlayer = true } label: {
                                Label("Add player", systemImage: "person.badge.plus")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(NeuroPulseColor.pantoneBlue)
                        }
                        .listRowBackground(Color.clear)
                    }

                    ForEach(baselineManager.teams.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { team in
                        let players = matchingAthletes.filter { $0.teamId == team.id }
                        if !players.isEmpty {
                            Section(team.name) {
                                ForEach(players) { athlete in playerRow(athlete) }
                            }
                        }
                    }

                    let unassigned = matchingAthletes.filter { id in
                        id.teamId == nil || !baselineManager.teams.contains(where: { $0.id == id.teamId })
                    }
                    if !unassigned.isEmpty {
                        Section("Unassigned") {
                            ForEach(unassigned) { athlete in playerRow(athlete) }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .searchable(text: $searchText, prompt: "Find a player")
            }
            .navigationTitle("Choose a player")
            .navigationInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAddPlayer = true } label: {
                        Label("Add player", systemImage: "plus")
                    }
                }
            }
        }
        .tint(NeuroPulseColor.pantoneBlue)
        .preferredColorScheme(.light)
        .sheet(isPresented: $showingAddPlayer, onDismiss: {
            // Finish dismissing the editor before closing its parent picker.
            if addedPlayer { dismiss() }
        }) {
            PlayerEditorView(title: "New player", saveTitle: "Add & select") { name, jersey, sport in
                let athlete = baselineManager.addAthlete(name: name, jerseyNumber: jersey, sport: sport)
                selectedAthleteId = athlete.id
                addedPlayer = true
            }
        }
    }

    private func playerRow(_ athlete: AthleteProfile) -> some View {
        Button {
            selectedAthleteId = athlete.id
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(NeuroPulseColor.pantoneBlue)
                VStack(alignment: .leading, spacing: 3) {
                    Text(athlete.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text(athlete.baseline == nil ? "No baseline yet" : "Baseline saved")
                        .font(.subheadline)
                        .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.72))
                }
                Spacer()
                if selectedAthleteId == athlete.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(NeuroPulseColor.pantoneBlue)
                }
            }
            .foregroundStyle(NeuroPulseColor.pantoneBlue)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(NeuroPulseColor.cardWhite)
    }
}
