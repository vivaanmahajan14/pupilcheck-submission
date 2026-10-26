import Foundation

public struct MotorMotionSample: Sendable {
    public let t: Double
    public let ax: Double, ay: Double, az: Double
    public let gx: Double, gy: Double, gz: Double
    public let rx: Double, ry: Double, rz: Double
    public init(t: Double, acceleration: (Double, Double, Double), gravity: (Double, Double, Double), rotation: (Double, Double, Double)) {
        self.t = t; (ax, ay, az) = acceleration; (gx, gy, gz) = gravity; (rx, ry, rz) = rotation
    }
}

public struct MotorTap: Sendable {
    public let t: Double
    public let side: Int
    public init(t: Double, side: Int) { self.t = t; self.side = side }
}

/// Native port of the branch's conservative quality gates. Metrics describe phone/touch behavior only.
public enum MotorTestAnalysis {
    /// A bundled-in-code 350 ms, 880 Hz PCM cue with short fades to avoid clicks.
    static func standingToneWAV() -> Data {
        let rate = 44_100
        let count = rate * 35 / 100
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func u16(_ value: UInt16) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        func u32(_ value: UInt32) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        text("RIFF"); u32(UInt32(36 + count * 2)); text("WAVEfmt ")
        u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
        text("data"); u32(UInt32(count * 2))
        for i in 0..<count {
            let fade = min(1, Double(min(i, count - 1 - i)) / 441)
            let sample = Int16((sin(2 * .pi * 880 * Double(i) / Double(rate)) * fade * 0.65 * 32767).rounded())
            u16(UInt16(bitPattern: sample))
        }
        return data
    }

    public static func reaction(times: [Double], early: Int, missed: Int, taps: [MotorTap], duration: Double, maxFrameGap: Double, multiTouch: Bool = false) -> MotorMeasurement {
        guard !multiTouch else { return MotorMeasurement(status: "insufficient_quality", reason: "More than one finger touched the screen; repeat using one finger.") }
        guard times.count >= 3, taps.count >= 4, abs(duration - 5) <= 0.1,
              maxFrameGap <= 0.1, times.allSatisfy({ (0.1...3).contains($0) }) else {
            return MotorMeasurement(status: "insufficient_quality", reason: "Need at least three valid reactions, at least four taps, five seconds of tapping, and uninterrupted screen updates.")
        }
        let ordered = taps.sorted { $0.t < $1.t }
        let intervals = zip(ordered, ordered.dropFirst()).map { $1.t - $0.t }
        guard intervals.allSatisfy({ $0 >= 0.04 }), ordered.allSatisfy({ $0.t >= 0 && $0.t <= duration && (0...1).contains($0.side) }) else {
            return MotorMeasurement(status: "insufficient_quality", reason: "Touch events overlapped or fell outside the test window; repeat.")
        }
        let alternating = zip(ordered, ordered.dropFirst()).compactMap { $0.side == $1.side ? nil : $1.t - $0.t }
        guard alternating.count >= 2 else {
            return MotorMeasurement(status: "insufficient_quality", reason: "Need at least two alternating tap intervals; repeat.")
        }
        let sorted = times.sorted()
        let reactionMedian = median(sorted)
        let intervalMedian = median(alternating)
        let range = times.max()! - times.min()!
        let metrics = Dictionary(uniqueKeysWithValues: times.enumerated().map { ("reaction_trial_\($0.offset + 1)_ms", $0.element * 1000) })
            .merging(["median_reaction_ms": reactionMedian * 1000, "reaction_range_ms": range * 1000,
                      "early_taps": Double(early), "missed_trials": Double(missed), "cadence_taps": Double(taps.count),
                      "alternations": Double(alternating.count), "same_side_errors": Double(intervals.count - alternating.count),
                      "alternations_per_second": Double(alternating.count) / duration,
                      "median_alternating_interval_ms": intervalMedian * 1000]) { _, new in new }
        return MotorMeasurement(status: "measured", metrics: metrics)
    }

    public static func balance(samples: [MotorMotionSample], duration: Double = 10) -> MotorMeasurement {
        guard duration.isFinite, abs(duration - 10) <= 0.1 else {
            return MotorMeasurement(status: "insufficient_quality", reason: String(format: "Recording timer measured %.2f seconds; expected 10 seconds within 0.10 seconds. The app timing was interrupted or delayed; repeat with the app open.", duration))
        }
        guard samples.count >= 200 else {
            return MotorMeasurement(status: "insufficient_quality", reason: "The phone delivered only \(samples.count) motion samples; at least 200 are required over ten seconds. This is a sensor capture issue, not a measure of how steadily you stood. Repeat with the app open.")
        }
        guard samples.allSatisfy({ sample in
            [sample.t, sample.ax, sample.ay, sample.az, sample.gx, sample.gy, sample.gz, sample.rx, sample.ry, sample.rz].allSatisfy(\.isFinite)
                && sample.t >= 0 && sample.t <= duration
        }) else {
            return MotorMeasurement(status: "insufficient_quality", reason: "Motion data contained invalid values or timestamps outside the recording window; repeat the test.")
        }
        let rows = samples.sorted { $0.t < $1.t }
        let gaps = zip(rows, rows.dropFirst()).map { $1.t - $0.t }
        guard rows.first!.t <= 0.15, duration - rows.last!.t <= 0.15,
              gaps.allSatisfy({ $0 > 0 }), gaps.max()! <= 0.15, median(gaps) <= 0.05 else {
            return MotorMeasurement(status: "insufficient_quality", reason: "Motion samples had gaps or insufficient coverage; repeat the full test.")
        }
        let rawGravity = rows.map { sample -> [Double] in
            let v = [sample.gx, sample.gy, sample.gz]
            let n = sqrt(v.reduce(0) { $0 + $1 * $1 })
            return n > 0 ? v.map { $0 / n } : [0, 0, 0]
        }
        guard rawGravity.allSatisfy({ row in row.allSatisfy(\.isFinite) && row.reduce(0, { $0 + $1 * $1 }) > 0.25 }) else {
            return MotorMeasurement(status: "insufficient_quality", reason: "Phone orientation data was unstable; repeat with the phone held against the chest.")
        }
        let grid = stride(from: 0.15, through: 9.85, by: 0.05).map { $0 }
        let times = rows.map(\.t)
        let acceleration = interpolate(rows.map { [$0.ax, $0.ay, $0.az] }, at: grid, sourceTimes: times)
        let gravity = interpolate(rawGravity, at: grid, sourceTimes: times).map { row -> [Double] in
            let length = sqrt(row.reduce(0) { $0 + $1 * $1 })
            return length > 0 ? row.map { $0 / length } : [0, 0, 0]
        }
        let reference = (0..<3).map { axis in gravity.reduce(0) { $0 + $1[axis] } / Double(gravity.count) }
        let norm = sqrt(reference.reduce(0) { $0 + $1 * $1 })
        guard norm >= 0.5 else { return MotorMeasurement(status: "insufficient_quality", reason: "Phone orientation changed too much; repeat.") }
        let ref = reference.map { $0 / norm }
        let tilt = gravity.map { row -> Double in
            let rowNorm = sqrt(row.reduce(0) { $0 + $1 * $1 })
            let cosine = max(-1, min(1, zip(row, ref).reduce(0) { $0 + $1.0 * $1.1 } / rowNorm))
            return acos(cosine) * 180 / .pi
        }
        guard (tilt.max() ?? 0) <= 45 else {
            return MotorMeasurement(status: "insufficient_quality", reason: "Phone orientation changed too much; keep it against the chest and repeat.")
        }
        let accelerationRMS = sqrt(acceleration.reduce(0) { $0 + $1.reduce(0) { $0 + $1 * $1 } } / Double(acceleration.count))
        let tiltRMS = sqrt(tilt.reduce(0) { $0 + $1 * $1 } / Double(tilt.count))
        let rotation = interpolate(rows.map { [$0.rx, $0.ry, $0.rz] }, at: grid, sourceTimes: times)
        let rotationRMS = sqrt(rotation.reduce(0) { $0 + $1.reduce(0) { $0 + pow($1 * 180 / .pi, 2) } } / Double(rotation.count))
        return MotorMeasurement(status: "measured", metrics: [
            "duration_seconds": duration, "sample_count": Double(rows.count), "median_sample_interval_ms": median(gaps) * 1000,
            "max_sample_gap_ms": (gaps.max() ?? 0) * 1000, "phone_acceleration_rms_m_s2": accelerationRMS,
            "phone_tilt_rms_deg": tiltRMS, "phone_tilt_peak_deg": tilt.max() ?? 0, "phone_rotation_rms_deg_s": rotationRMS
        ])
    }

    private static func interpolate(_ values: [[Double]], at targets: [Double], sourceTimes: [Double]) -> [[Double]] {
        var index = 0
        return targets.map { time in
            while index + 1 < sourceTimes.count - 1 && sourceTimes[index + 1] < time { index += 1 }
            let fraction = (time - sourceTimes[index]) / (sourceTimes[index + 1] - sourceTimes[index])
            return zip(values[index], values[index + 1]).map { $0 + ($1 - $0) * fraction }
        }
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted(); guard !sorted.isEmpty else { return .infinity }
        return sorted.count.isMultiple(of: 2) ? (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2 : sorted[sorted.count / 2]
    }
}
