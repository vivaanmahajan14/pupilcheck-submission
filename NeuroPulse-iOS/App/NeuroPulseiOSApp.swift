import SwiftUI
import NeuroPulse

/// Native iOS Application Entry Point for NeuroPulse.
@main
struct NeuroPulseiOSApp: App {
    var body: some Scene {
        WindowGroup {
            NeuroPulseRootView()
                .preferredColorScheme(.light)
        }
    }
}
