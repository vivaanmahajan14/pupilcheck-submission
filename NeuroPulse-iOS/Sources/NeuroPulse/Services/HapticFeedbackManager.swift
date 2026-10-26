import Foundation
#if canImport(UIKit)
import UIKit
import AudioToolbox
#endif

/// High-precision tactile and audio feedback engine.
/// Provides immediate, latency-free physical feedback for calibration lock,
/// countdown ticks, and phase transitions to eliminate user confusion on the sideline.
public final class HapticFeedbackManager: @unchecked Sendable {
    public static let shared = HapticFeedbackManager()

    #if canImport(UIKit)
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
    private let notificationFeedback = UINotificationFeedbackGenerator()
    #endif

    public init() {
        #if canImport(UIKit)
        lightImpact.prepare()
        mediumImpact.prepare()
        rigidImpact.prepare()
        notificationFeedback.prepare()
        #endif
    }

    /// Fired when an optical calibration anchor locks successfully.
    /// Delivers an unmistakable tactile punch and audio chirp.
    public func calibrationLockSuccess() {
        #if canImport(UIKit)
        DispatchQueue.main.async {
            self.rigidImpact.impactOccurred()
            self.notificationFeedback.notificationOccurred(.success)
            AudioServicesPlaySystemSound(1057) // Camera shutter / lock chirp
        }
        #else
        print("🔊 [Haptic] Calibration Locked Successfully!")
        #endif
    }

    /// Fired on each tick of the 3-2-1 auto-countdown.
    public func countdownTick() {
        #if canImport(UIKit)
        DispatchQueue.main.async {
            self.lightImpact.impactOccurred()
            AudioServicesPlaySystemSound(1104) // Sharp tick
        }
        #else
        print("🔊 [Haptic] Countdown Tick")
        #endif
    }

    /// Fired when the countdown reaches 0 and the exam begins.
    public func examStart() {
        #if canImport(UIKit)
        DispatchQueue.main.async {
            self.mediumImpact.impactOccurred()
            AudioServicesPlaySystemSound(1054)
        }
        #else
        print("🔊 [Haptic] Exam Started!")
        #endif
    }

    /// Fired when user moves out of the optimal 20–44 cm distance window.
    public func distanceWarning() {
        #if canImport(UIKit)
        DispatchQueue.main.async {
            self.notificationFeedback.notificationOccurred(.warning)
        }
        #else
        print("⚠️ [Haptic] Distance Warning")
        #endif
    }

    /// Fired when entire examination battery finishes.
    public func examComplete() {
        #if canImport(UIKit)
        DispatchQueue.main.async {
            self.notificationFeedback.notificationOccurred(.success)
            AudioServicesPlaySystemSound(1001)
        }
        #else
        print("🎉 [Haptic] Exam Completed!")
        #endif
    }
}
