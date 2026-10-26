import XCTest
import AVFoundation
@testable import NeuroPulse

final class MotorCaptureStateTests: XCTestCase {
    func testStandingCueIsDecodableNonSilentAudio() throws {
        let data = MotorTestAnalysis.standingToneWAV()
        let player = try AVAudioPlayer(data: data)
        XCTAssertEqual(player.duration, 0.35, accuracy: 0.001)
        XCTAssertEqual(player.numberOfChannels, 1)
        XCTAssertEqual(data.count, 44 + 15_435 * 2)
        let bytes = [UInt8](data.dropFirst(44))
        let samples = stride(from: 0, to: bytes.count, by: 2).map {
            Int16(bitPattern: UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8)
        }
        XCTAssertEqual(samples.first, 0)
        XCTAssertEqual(samples.last, 0)
        let peak = samples.map { abs(Int($0)) }.max() ?? 0
        XCTAssertGreaterThan(peak, 20_000)
        XCTAssertLessThan(peak, 32_767)
    }

    func testSoundPlaybackDoesNotConfirmAudibility() {
        var capture = MotorCaptureState()
        capture.tonePlayed = true
        XCTAssertFalse(capture.soundConfirmed)
        capture.heardTone = true
        XCTAssertTrue(capture.soundConfirmed)
        capture.resetSound()
        XCTAssertFalse(capture.soundConfirmed)
        capture.heardTone = true
        XCTAssertFalse(capture.soundConfirmed, "Confirmation without playing a tone is insufficient")
    }

    func testInterruptionRequiresFreshCaptureAndSoundConfirmation() {
        for stage in [MotorCaptureState.Stage.reaction, .cadence] {
            var capture = MotorCaptureState(stage: stage, tonePlayed: true, heardTone: true)
            XCTAssertEqual(capture.interrupt(), .reaction)
            XCTAssertEqual(capture.stage, .intro)
            XCTAssertFalse(capture.soundConfirmed)
        }
        for stage in [MotorCaptureState.Stage.eyesOpen, .eyesClosed] {
            var capture = MotorCaptureState(stage: stage, tonePlayed: true, heardTone: true)
            XCTAssertEqual(capture.interrupt(), .balance)
            XCTAssertEqual(capture.stage, .balanceSetup)
            XCTAssertFalse(capture.soundConfirmed)
        }
    }

    func testInterruptionDoesNotDiscardCompletedResultsOrStartIdleTests() {
        for stage in [MotorCaptureState.Stage.intro, .balanceSetup, .results] {
            var capture = MotorCaptureState(stage: stage, tonePlayed: true, heardTone: true)
            XCTAssertNil(capture.interrupt())
            XCTAssertEqual(capture.stage, stage)
            XCTAssertFalse(capture.soundConfirmed)
        }
    }

}
