import SwiftUI

/// Team and player management for the coach's local roster.
public struct AthleteRosterView: View {
    @ObservedObject private var baselineManager: BaselineManager
    private let onSetBaseline: (AthleteProfile) -> Void

    @State private var showingAddTeam = false

    public init(
        baselineManager: BaselineManager,
        onSetBaseline: @escaping (AthleteProfile) -> Void = { _ in }
    ) {
        self.baselineManager = baselineManager
        self.onSetBaseline = onSetBaseline
    }

    public var body: some View {
        ZStack {
            NeuroPulseColor.pantoneYellowCanvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Build your roster")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(NeuroPulseColor.pantoneBlue)
                        Text("Create a team, then add the players you coach. Their baseline and recordings stay with their profile.")
                            .font(.subheadline)
                            .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if baselineManager.teams.isEmpty && baselineManager.athletes.isEmpty {
                        emptyTeamsCard
                    } else {
                        if !baselineManager.teams.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                sectionLabel("TEAMS")
                                ForEach(sortedTeams) { team in
                                    NavigationLink {
                                        TeamDetailView(
                                            baselineManager: baselineManager,
                                            teamId: team.id,
                                            onSetBaseline: onSetBaseline
                                        )
                                    } label: {
                                        TeamRow(team: team, playerCount: playerCount(for: team.id))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        if !unassignedPlayers.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                sectionLabel("UNASSIGNED PLAYERS")
                                NavigationLink {
                                    TeamDetailView(
                                        baselineManager: baselineManager,
                                        teamId: nil,
                                        onSetBaseline: onSetBaseline
                                    )
                                } label: {
                                    TeamRow(title: "Unassigned", subtitle: "Add these players to a team", playerCount: unassignedPlayers.count, symbol: "person.crop.circle.badge.questionmark")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Teams")
        .navigationInlineTitle()
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { showingAddTeam = true } label: {
                    Label("Add team", systemImage: "plus")
                }
                .accessibilityLabel("Add a team")
            }
        }
        .sheet(isPresented: $showingAddTeam) {
            TeamEditorView(title: "New team", saveTitle: "Create team") { name, sport in
                _ = baselineManager.addTeam(name: name, sport: sport)
            }
        }
    }

    private var emptyTeamsCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.3.sequence.fill")
                .font(.system(size: 32))
                .foregroundStyle(NeuroPulseColor.pantoneBlue)
                .frame(width: 68, height: 68)
                .background(NeuroPulseColor.pantoneBlueSurface)
                .clipShape(Circle())
            Text("Start with a team")
                .font(.title3.weight(.bold))
                .foregroundStyle(NeuroPulseColor.pantoneBlue)
            Text("Add your first team, then create player profiles and save a personal baseline for each player.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.72))
            Button { showingAddTeam = true } label: {
                Label("Create a team", systemImage: "plus")
                    .font(.headline)
                    .foregroundStyle(NeuroPulseColor.cardWhite)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(NeuroPulseColor.pantoneBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(NeuroPulseColor.cardWhite)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var sortedTeams: [TeamProfile] {
        baselineManager.teams.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var unassignedPlayers: [AthleteProfile] {
        baselineManager.athletes.filter { athlete in
            athlete.teamId == nil || !baselineManager.teams.contains(where: { $0.id == athlete.teamId })
        }
    }

    private func playerCount(for teamId: String) -> Int {
        baselineManager.athletes.filter { $0.teamId == teamId }.count
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .tracking(1)
            .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.58))
    }
}

private struct TeamRow: View {
    let title: String
    let subtitle: String
    let playerCount: Int
    let symbol: String

    init(team: TeamProfile, playerCount: Int) {
        title = team.name
        subtitle = team.sport.isEmpty ? "Team roster" : team.sport
        self.playerCount = playerCount
        symbol = "person.3.fill"
    }

    init(title: String, subtitle: String, playerCount: Int, symbol: String) {
        self.title = title
        self.subtitle = subtitle
        self.playerCount = playerCount
        self.symbol = symbol
    }

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(NeuroPulseColor.pantoneBlue)
                .frame(width: 46, height: 46)
                .background(NeuroPulseColor.pantoneBlueSurface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).fixedSize(horizontal: false, vertical: true).foregroundStyle(NeuroPulseColor.pantoneBlue)
                Text(subtitle).font(.subheadline).foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.64))
            }
            Spacer()
            Text("\(playerCount)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.72))
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.42))
        }
        .appSurface()
    }
}

private struct TeamDetailView: View {
    @ObservedObject var baselineManager: BaselineManager
    let teamId: String?
    let onSetBaseline: (AthleteProfile) -> Void

    @State private var showingAddPlayer = false
    @State private var showingEditTeam = false
    @State private var showingDeleteConfirmation = false
    @Environment(\.dismiss) private var dismiss

    private var team: TeamProfile? { teamId.flatMap { id in baselineManager.teams.first(where: { $0.id == id }) } }
    private var title: String { team?.name ?? "Unassigned" }
    private var players: [AthleteProfile] {
        baselineManager.athletes
            .filter { athlete in
                teamId == nil
                    ? (athlete.teamId == nil || !baselineManager.teams.contains(where: { team in team.id == athlete.teamId }))
                    : athlete.teamId == teamId
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        ZStack {
            NeuroPulseColor.pantoneYellowCanvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let team, !team.sport.isEmpty {
                        Text(team.sport)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.66))
                    }

                    if players.isEmpty {
                        ContentUnavailableView {
                            Label("No players yet", systemImage: "person.crop.circle.badge.plus")
                                .foregroundStyle(NeuroPulseColor.pantoneBlue)
                        } description: {
                            Text("Add a player profile to keep their baseline and recordings together.")
                                .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.8))
                        } actions: {
                            Button("Add player") { showingAddPlayer = true }
                                .buttonStyle(.borderedProminent)
                                .tint(NeuroPulseColor.pantoneBlue)
                        }
                        .padding(.top, 30)
                    } else {
                        ForEach(players) { athlete in
                            NavigationLink {
                                PlayerDetailView(
                                    baselineManager: baselineManager,
                                    athleteId: athlete.id,
                                    onSetBaseline: onSetBaseline
                                )
                            } label: {
                                PlayerRow(athlete: athlete)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(title)
        .navigationInlineTitle()
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if team != nil {
                    Menu {
                        Button("Edit team", systemImage: "pencil") { showingEditTeam = true }
                        Button("Delete team", systemImage: "trash", role: .destructive) { showingDeleteConfirmation = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .accessibilityLabel("Team options")
                    }
                }
            }
            ToolbarItem(placement: .automatic) {
                Button { showingAddPlayer = true } label: {
                    Label("Add player", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .sheet(isPresented: $showingAddPlayer) {
            PlayerEditorView(title: "New player", saveTitle: "Add player") { name, jersey, sport in
                _ = baselineManager.addAthlete(name: name, jerseyNumber: jersey, sport: sport, teamId: teamId)
            }
        }
        .sheet(isPresented: $showingEditTeam) {
            if let team {
                TeamEditorView(title: "Edit team", saveTitle: "Save changes", initialName: team.name, initialSport: team.sport) { name, sport in
                    baselineManager.updateTeam(id: team.id, name: name, sport: sport)
                }
            }
        }
        .confirmationDialog("Delete \(title)?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete team", role: .destructive) {
                if let teamId { baselineManager.deleteTeam(id: teamId) }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Players, baselines, and recordings will stay saved under Unassigned.")
        }
    }
}

private struct PlayerRow: View {
    let athlete: AthleteProfile

    var body: some View {
        HStack(spacing: 12) {
            Text(athlete.name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased())
                .font(.subheadline.weight(.bold).monospaced())
                .foregroundStyle(NeuroPulseColor.pantoneBlue)
                .frame(width: 48, height: 48)
                .background(NeuroPulseColor.pantoneBlueSurface)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(athlete.name).font(.headline).fixedSize(horizontal: false, vertical: true).foregroundStyle(NeuroPulseColor.pantoneBlue)
                Text(athlete.baseline.map { "Baseline · \(dateLabel($0.recordedAt))" } ?? "No baseline yet")
                    .font(.subheadline)
                    .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.65))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.42))
        }
        .padding(13)
        .background(NeuroPulseColor.cardWhite)
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
    }
}

private struct PlayerDetailView: View {
    @ObservedObject var baselineManager: BaselineManager
    let athleteId: String
    let onSetBaseline: (AthleteProfile) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingEditPlayer = false
    @State private var showingDeleteConfirmation = false
    @State private var showingHistoryResult: SCAT6TriageResult?
    @State private var showingMotorResult: MotorTestSession?

    private var athlete: AthleteProfile? { baselineManager.getAthlete(id: athleteId) }

    var body: some View {
        ZStack {
            NeuroPulseColor.pantoneYellowCanvas.ignoresSafeArea()
            if let athlete {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        playerHeader(athlete)
                        baselineCard(athlete)
                        historySection(athlete)
                    }
                    .padding(20)
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity)
                }
            } else {
                ContentUnavailableView("Player removed", systemImage: "person.crop.circle.badge.xmark")
            }
        }
        .navigationTitle(athlete?.name ?? "Player")
        .navigationInlineTitle()
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    if let athlete {
                        Button(athlete.baseline == nil ? "Set baseline" : "Replace baseline", systemImage: "bookmark") {
                            onSetBaseline(athlete)
                        }
                        Button("Edit player", systemImage: "pencil") { showingEditPlayer = true }
                        Menu("Move to team") {
                            Button("Unassigned") { baselineManager.moveAthlete(id: athlete.id, toTeamId: nil) }
                            ForEach(baselineManager.teams.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { team in
                                Button(team.name) { baselineManager.moveAthlete(id: athlete.id, toTeamId: team.id) }
                            }
                        }
                        Button("Delete player", systemImage: "trash", role: .destructive) { showingDeleteConfirmation = true }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel("Player options")
                }
            }
        }
        .sheet(isPresented: $showingEditPlayer) {
            if let athlete {
                PlayerEditorView(title: "Edit player", saveTitle: "Save changes", initialName: athlete.name, initialJersey: athlete.jerseyNumber, initialSport: athlete.sport) { name, jersey, sport in
                    baselineManager.updateAthlete(id: athlete.id, name: name, jerseyNumber: jersey, sport: sport)
                }
            }
        }
        .sheet(item: $showingHistoryResult) { result in
            ResultsView(result: result, onDone: { showingHistoryResult = nil },
                motorSession: baselineManager.motorSession(athleteId: athleteId, eyeResultID: result.id))
        }
        .sheet(item: $showingMotorResult) { session in
            NavigationStack {
                ScrollView { MotorResultsSection(session: session).padding(20) }
                    .background(NeuroPulseColor.pantoneYellowCanvas)
                    .navigationTitle("Reaction & standing")
                    .toolbar { Button("Done") { showingMotorResult = nil } }
            }
            .tint(NeuroPulseColor.pantoneBlue)
            .preferredColorScheme(.light)
        }
        .confirmationDialog("Delete this player?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete player", role: .destructive) {
                baselineManager.deleteAthlete(id: athleteId)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This also removes this player's saved baseline and recording history.")
        }
    }

    private func playerHeader(_ athlete: AthleteProfile) -> some View {
        HStack(spacing: 15) {
            Text(athlete.name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased())
                .font(.title3.weight(.bold).monospaced())
                .foregroundStyle(NeuroPulseColor.pantoneBlue)
                .frame(width: 64, height: 64)
                .background(NeuroPulseColor.pantoneBlueSurface)
                .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(athlete.name).font(.title2.weight(.bold)).fixedSize(horizontal: false, vertical: true).foregroundStyle(NeuroPulseColor.pantoneBlue)
                Text([athlete.sport, baselineManager.teams.first(where: { $0.id == athlete.teamId })?.name ?? "Unassigned"]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.68))
            }
            Spacer(minLength: 0)
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NeuroPulseColor.cardWhite)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func baselineCard(_ athlete: AthleteProfile) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("PERSONAL BASELINE")
                .font(.caption.weight(.bold))
                .tracking(1)
                .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.58))
            if let baseline = athlete.baseline {
                Label("Reference saved", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(NeuroPulseColor.pantoneBlue)
                Text("Recorded \(dateLabel(baseline.recordedAt)). Future sessions can show descriptive differences from this recording.")
                    .font(.subheadline)
                    .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Reaction: \(athlete.reactionReference == nil ? "not saved" : "reference saved") · Standing: \(athlete.balanceReference == nil ? "not saved" : "reference saved")")
                    .font(.caption)
                    .foregroundStyle(NeuroPulseColor.pantoneBlue)
                Button { onSetBaseline(athlete) } label: {
                    Label("Replace baseline", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.top, 2)
            } else {
                Text("No baseline yet")
                    .font(.headline)
                    .foregroundStyle(NeuroPulseColor.pantoneBlue)
                Text("A baseline is a personal reference recording. It does not diagnose an injury.")
                    .font(.subheadline)
                    .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
                Button { onSetBaseline(athlete) } label: {
                    Label("Set baseline", systemImage: "bookmark")
                        .font(.headline)
                        .foregroundStyle(NeuroPulseColor.cardWhite)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(NeuroPulseColor.pantoneBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NeuroPulseColor.cardWhite)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private func historySection(_ athlete: AthleteProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RECORDING HISTORY")
                .font(.caption.weight(.bold))
                .tracking(1)
                .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.58))
            if athlete.triageHistory.isEmpty {
                Text("Saved recordings will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(NeuroPulseColor.pantoneBlue.opacity(0.65))
                    .padding(15)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NeuroPulseColor.cardWhite)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                ForEach(athlete.triageHistory) { record in
                    Button { showingHistoryResult = record } label: {
                        RecordingSummaryRow(
                            record: record,
                            detail: (athlete.motorHistory ?? []).contains { $0.eyeResultID == record.id }
                                ? "Eye + motor results saved" : "Eyes · tests 3 & 4 not saved",
                            badgeColor: badgeColor(for: record)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            ForEach((athlete.motorHistory ?? []).filter { session in
                !athlete.triageHistory.contains { $0.id == session.eyeResultID }
            }) { session in
                Button { showingMotorResult = session } label: {
                    Label("Reaction & standing · \(dateLabel(session.date))", systemImage: "chart.bar")
                        .font(.subheadline)
                        .foregroundStyle(NeuroPulseColor.pantoneBlue)
                        .padding(15)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(NeuroPulseColor.cardWhite)
                        .clipShape(RoundedRectangle(cornerRadius: 15))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func badgeColor(for record: SCAT6TriageResult) -> Color {
        NeuroPulseColor.pantoneBlue
    }
}

private struct TeamEditorView: View {
    let title: String
    let saveTitle: String
    var initialName = ""
    var initialSport = ""
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var sport: String

    init(title: String, saveTitle: String, initialName: String = "", initialSport: String = "", onSave: @escaping (String, String) -> Void) {
        self.title = title
        self.saveTitle = saveTitle
        self.initialName = initialName
        self.initialSport = initialSport
        self.onSave = onSave
        _name = State(initialValue: initialName)
        _sport = State(initialValue: initialSport)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Team") {
                    TextField("Team name", text: $name)
                    TextField("Sport (optional)", text: $sport)
                }
            }
            .navigationTitle(title)
            .navigationInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveTitle) {
                        onSave(name.trimmingCharacters(in: .whitespacesAndNewlines), sport.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .tint(NeuroPulseColor.pantoneBlue)
        .preferredColorScheme(.light)
    }
}

/// Shared by team management and the test home’s player picker.
struct PlayerEditorView: View {
    let title: String
    let saveTitle: String
    let onSave: (String, String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var jersey: String
    @State private var sport: String

    init(title: String, saveTitle: String, initialName: String = "", initialJersey: String = "", initialSport: String = "", onSave: @escaping (String, String, String) -> Void) {
        self.title = title
        self.saveTitle = saveTitle
        self.onSave = onSave
        _name = State(initialValue: initialName)
        _jersey = State(initialValue: initialJersey)
        _sport = State(initialValue: initialSport)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Player") {
                    TextField("Player name", text: $name)
                    TextField("Jersey number (optional)", text: $jersey)
                    TextField("Position or sport (optional)", text: $sport)
                }
            }
            .navigationTitle(title)
            .navigationInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveTitle) {
                        onSave(
                            name.trimmingCharacters(in: .whitespacesAndNewlines),
                            jersey.trimmingCharacters(in: .whitespacesAndNewlines),
                            sport.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .tint(NeuroPulseColor.pantoneBlue)
        .preferredColorScheme(.light)
    }
}

private func dateLabel(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .shortened)
}
