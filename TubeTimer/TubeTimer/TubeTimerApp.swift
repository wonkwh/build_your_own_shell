import SwiftUI

@main
struct TubeTimerApp: App {
    init() {
        Typography.setUp()
    }

    var body: some Scene {
        WindowGroup {
            SetupView()
                .font(.nunito(.body))
                .tint(Theme.accent)
        }
    }
}
