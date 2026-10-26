import SwiftUI

/// Root visual view of the NeuroPulse application.
public struct NeuroPulseRootView: View {
    public init() {}

    public var body: some View {
        DashboardView()
    }
}

#if APP_ENTRY
@main
public struct NeuroPulseApp: App {
    public init() {}

    public var body: some Scene {
        WindowGroup {
            NeuroPulseRootView()
        }
    }
}
#endif
