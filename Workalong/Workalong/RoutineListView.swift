import SwiftData
import SwiftUI

/// 홈. 루틴 목록, + 로 추가, 밀어서 삭제
struct RoutineListView: View {
    @Query(sort: \Routine.createdAt) private var routines: [Routine]
    @Environment(\.modelContext) private var context
    @State private var path: [Routine] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(routines) { routine in
                    NavigationLink(value: routine) {
                        RoutineRow(routine: routine)
                    }
                }
                .onDelete(perform: delete)
                .listRowBackground(Theme.surface)
            }
            .themedList()
            .overlay {
                if routines.isEmpty {
                    ContentUnavailableView("루틴이 없어요", systemImage: "timer", description: Text("+ 를 눌러 첫 루틴을 만들어요"))
                }
            }
            .navigationTitle("루틴")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Routine.self) { SetupView(routine: $0) }
            .toolbar {
                Button("루틴 추가", systemImage: "plus", action: add)
            }
        }
    }

    private func add() {
        let routine = Routine(name: Routine.newName)
        context.insert(routine)
        try? context.save()
        path.append(routine)
    }

    private func delete(_ offsets: IndexSet) {
        offsets.map { routines[$0] }.forEach(context.delete)
        try? context.save()
    }
}

private struct RoutineRow: View {
    let routine: Routine

    var body: some View {
        HStack(spacing: 12) {
            VideoThumbnail(source: routine.video, radius: 8)
                .frame(width: 96)
            VStack(alignment: .leading, spacing: 4) {
                Text(routine.name.isEmpty ? String(localized: "이름 없음") : routine.name)
                    .font(.nunito(.headline))
                    .lineLimit(2)
                Text("\(routine.sets)세트 · 총 \(clock(routine.plan.total))")
                    .font(.nunito(.subheadline, .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    RoutineListView()
        .modelContainer(for: Routine.self, inMemory: true)
}
