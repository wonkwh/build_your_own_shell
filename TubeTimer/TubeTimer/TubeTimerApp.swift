import SwiftData
import SwiftUI

@main
struct TubeTimerApp: App {
    let container: ModelContainer

    init() {
        Typography.setUp()
        do {
            container = try ModelContainer(for: Routine.self)
            try Routine.seedIfNeeded(in: container.mainContext)
        } catch {
            fatalError("루틴 저장소를 열지 못했어요: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .font(.nunito(.body))
                .tint(Theme.accent)
        }
        .modelContainer(container)
    }
}

/// ponytail: 첫 루틴만 연다. 2단계에서 루틴 목록으로 바꾼다
private struct RootView: View {
    @Query(sort: \Routine.createdAt) private var routines: [Routine]

    var body: some View {
        if let routine = routines.first {
            SetupView(routine: routine)
        }
    }
}
