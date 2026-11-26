import SwiftData
import SwiftUI

@main
struct WorkalongApp: App {
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
            RoutineListView()
                .font(.nunito(.body))
                .tint(Theme.accent)
        }
        .modelContainer(container)
    }
}
