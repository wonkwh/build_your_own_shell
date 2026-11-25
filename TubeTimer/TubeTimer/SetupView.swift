import SwiftData
import SwiftUI

/// 인터벌 설정. Life Reset 의 세 항목에 Breathwrk·Opal 의 큰 − / + 스테퍼를 붙였다
struct SetupView: View {
    @Bindable var routine: Routine
    @State private var isRunning = false
    @Environment(\.modelContext) private var context

    private var plan: IntervalPlan { routine.plan }

    var body: some View {
        NavigationStack {
            CardScroll {
                CardSection(footer: Text("총 \(clock(plan.total))")) {
                    StepperRow(title: "세트", value: $routine.sets, range: 1...99) { "\($0)" }
                    StepperRow(title: "운동", value: $routine.work, range: 5...3600, step: 5, format: clock)
                    StepperRow(title: "휴식", value: $routine.rest, range: 0...3600, step: 5, format: clock)
                }
            }
            // 자동 저장을 기다리다 앱이 종료되면 바꾼 값을 잃으므로 바로 저장한다
            .onChange(of: plan) { try? context.save() }
            .navigationTitle("인터벌 타이머")
            .navigationBarTitleDisplayMode(.inline)
            .bottomAction {
                Button("시작") { isRunning = true }
            }
            .fullScreenCover(isPresented: $isRunning) {
                RunView(plan: plan)
            }
        }
    }
}

/// 라벨 + 큰 값을 가운데 둔 − / + 스테퍼. 버튼을 누르고 있으면 계속 바뀐다
private struct StepperRow: View {
    let title: LocalizedStringKey
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    let format: (Int) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.nunito(.subheadline, .medium))
                .foregroundStyle(.secondary)
            HStack {
                Button("빼기", systemImage: "minus", action: decrement)
                    .disabled(value <= range.lowerBound)
                Text(format(value))
                    .font(.display(44))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText(value: Double(value)))
                    .frame(maxWidth: .infinity)
                Button("더하기", systemImage: "plus", action: increment)
                    .disabled(value >= range.upperBound)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.round)
            .buttonRepeatBehavior(.enabled)
            .animation(.default, value: value)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(format(value))
        .accessibilityAdjustableAction { direction in
            direction == .increment ? increment() : decrement()
        }
    }

    private func increment() { value = min(range.upperBound, value + step) }
    private func decrement() { value = max(range.lowerBound, value - step) }
}

#Preview {
    SetupView(routine: Routine())
        .modelContainer(for: Routine.self, inMemory: true)
}
