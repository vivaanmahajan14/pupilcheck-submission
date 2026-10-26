import Foundation
import Combine

/// Local data management for teams, players, baselines, and experimental recordings.
public final class BaselineManager: ObservableObject {
    public static let shared = BaselineManager()

    @Published public var athletes: [AthleteProfile] = []
    @Published public var teams: [TeamProfile] = []

    private let storageKey = "neuropulse_athlete_roster_v3"
    private let teamsStorageKey = "neuropulse_teams_v1"
    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        loadAthletes()
        loadTeams()
    }

    // MARK: - Athlete Roster Management
    public func loadAthletes() {
        let decoder = JSONDecoder()
        let current = userDefaults.data(forKey: storageKey).flatMap { try? decoder.decode([AthleteProfile].self, from: $0) } ?? []
        let previous = userDefaults.bool(forKey: "neuropulse_roster_migrated_v2") ? [] : userDefaults.data(forKey: "neuropulse_athlete_roster_v2").flatMap { try? decoder.decode([AthleteProfile].self, from: $0) } ?? []
        let currentIDs = Set(current.map(\.id))
        athletes = current + previous.filter { !currentIDs.contains($0.id) }
        if !userDefaults.bool(forKey: "neuropulse_roster_migrated_v2"),
           let encoded = try? JSONEncoder().encode(athletes) {
            userDefaults.set(encoded, forKey: storageKey)
            userDefaults.set(true, forKey: "neuropulse_roster_migrated_v2")
        }
    }

    public func saveToStorage() {
        if let encoded = try? JSONEncoder().encode(athletes) {
            userDefaults.set(encoded, forKey: storageKey)
        }
    }

    public func loadTeams() {
        guard let data = userDefaults.data(forKey: teamsStorageKey),
              let decoded = try? JSONDecoder().decode([TeamProfile].self, from: data) else {
            teams = []
            return
        }
        teams = decoded
    }

    private func saveTeams() {
        guard let encoded = try? JSONEncoder().encode(teams) else { return }
        userDefaults.set(encoded, forKey: teamsStorageKey)
    }

    @discardableResult
    public func addTeam(name: String, sport: String = "") -> TeamProfile {
        let team = TeamProfile(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            sport: sport.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        teams.append(team)
        saveTeams()
        return team
    }

    public func updateTeam(id: String, name: String, sport: String) {
        guard let index = teams.firstIndex(where: { $0.id == id }) else { return }
        teams[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        teams[index].sport = sport.trimmingCharacters(in: .whitespacesAndNewlines)
        saveTeams()
    }

    /// Removing a team keeps its players, baselines, and recording history under Unassigned.
    public func deleteTeam(id: String) {
        teams.removeAll { $0.id == id }
        for index in athletes.indices where athletes[index].teamId == id {
            athletes[index].teamId = nil
        }
        saveTeams()
        saveToStorage()
    }

    public func moveAthlete(id: String, toTeamId teamId: String?) {
        guard let index = athletes.firstIndex(where: { $0.id == id }) else { return }
        guard teamId == nil || teams.contains(where: { $0.id == teamId }) else { return }
        athletes[index].teamId = teamId
        saveToStorage()
    }

    public func updateAthlete(id: String, name: String, jerseyNumber: String, sport: String) {
        guard let index = athletes.firstIndex(where: { $0.id == id }) else { return }
        athletes[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        athletes[index].jerseyNumber = jerseyNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        athletes[index].sport = sport.trimmingCharacters(in: .whitespacesAndNewlines)
        saveToStorage()
    }

    public func deleteAthlete(id: String) {
        athletes.removeAll(where: { $0.id == id })
        saveToStorage()
    }

    public func getAthlete(id: String) -> AthleteProfile? {
        athletes.first(where: { $0.id == id })
    }

    public func getBaseline(athleteId: String) -> BaselineBiometrics? {
        guard let athlete = athletes.first(where: { $0.id == athleteId }), let baseline = athlete.baseline else { return nil }
        // Older app versions could save a failed calibration as a reference.
        if let source = athlete.triageHistory.first(where: { $0.isBaselineTest && $0.timestamp == baseline.recordedAt }),
           !RecordingOverview.canUseEyeReference(source) { return nil }
        return baseline
    }

    public func saveBaseline(athleteId: String, baseline: BaselineBiometrics) {
        if let index = athletes.firstIndex(where: { $0.id == athleteId }) {
            athletes[index].baseline = baseline
            saveToStorage()
        }
    }

    public func recordTriageResult(athleteId: String, result: SCAT6TriageResult) {
        if let index = athletes.firstIndex(where: { $0.id == athleteId }) {
            athletes[index].triageHistory.insert(result, at: 0)
            if result.isBaselineTest && RecordingOverview.canUseEyeReference(result) {
                let newBaseline = BaselineBiometrics(
                    athleteId: athleteId,
                    recordedAt: result.timestamp,
                    pursuitGain: result.pursuitGain,
                    latencyLagMs: result.latencyLagMs,
                    fixationStabilityPercent: result.fixationStabilityPercent,
                    driftVelocity: result.driftVelocity,
                    twitchesCount: result.correctiveTwitches,
                    protocolVersion: result.recording?.qualityMetadata?.protocolVersion ?? AppConstants.CalibrationGrid.protocolVersion
                )
                athletes[index].baseline = newBaseline
            }
            saveToStorage()
        }
    }

    public func motorSession(for result: SCAT6TriageResult, reaction: MotorMeasurement, balance: MotorMeasurement) -> MotorTestSession {
        let athlete = getAthlete(id: result.athleteId)
        return MotorTestSession(eyeResultID: result.id, reaction: reaction, balance: balance,
            isBaseline: result.isBaselineTest,
            reactionReference: result.isBaselineTest ? nil : athlete?.reactionReference,
            balanceReference: result.isBaselineTest ? nil : athlete?.balanceReference)
    }

    public func recordMotorSession(athleteId: String, session: MotorTestSession) {
        guard let index = athletes.firstIndex(where: { $0.id == athleteId }),
              !(athletes[index].motorHistory ?? []).contains(where: { $0.id == session.id }) else { return }
        athletes[index].motorHistory = [session] + (athletes[index].motorHistory ?? [])
        if session.isBaseline == true {
            if session.reaction.canBeReference {
                athletes[index].reactionReference = MotorReference(recordedAt: session.date, measurement: session.reaction)
            }
            if session.balance.canBeReference {
                athletes[index].balanceReference = MotorReference(recordedAt: session.date, measurement: session.balance)
            }
        }
        saveToStorage()
    }

    public func motorSession(athleteId: String, eyeResultID: UUID) -> MotorTestSession? {
        getAthlete(id: athleteId)?.motorHistory?.first { $0.eyeResultID == eyeResultID }
    }

    public func addAthlete(
        name: String,
        jerseyNumber: String = "",
        sport: String = "",
        school: String = "",
        teamId: String? = nil
    ) -> AthleteProfile {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanJersey = jerseyNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSport = sport.trimmingCharacters(in: .whitespacesAndNewlines)
        let newAthlete = AthleteProfile(
            id: UUID().uuidString,
            name: cleanName.isEmpty ? "Participant" : cleanName,
            jerseyNumber: cleanJersey,
            sport: cleanSport,
            school: school.trimmingCharacters(in: .whitespacesAndNewlines),
            teamId: teamId
        )
        athletes.append(newAthlete)
        saveToStorage()
        return newAthlete
    }
}
