import SwiftUI

/// 실행 화면. Gymshark 휴식 시트처럼 큰 링 카운트다운, 건너뛰기, −10초 / +10초
struct RunView: View {
    let video: VideoSource?
    let workout: Workout?
    @State private var run: IntervalRun
    @State private var startedAt = Date.now
    @State private var isLogged = false
    @Environment(\.dismiss) private var dismiss

    init(plan: IntervalPlan, video: VideoSource? = nil, workout: Workout? = nil) {
        self.video = video
        self.workout = workout
        _run = State(initialValue: IntervalRun(plan: plan))
    }

    private var isDone: Bool { run.phase == .done }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                if let video {
                    VideoPlayerView(source: video)
                } else {
                    Spacer()
                }
                ring
                HStack(spacing: 12) {
                    Button("−10초") { run.add(-10) }
                    Button("+10초") { run.add(10) }
                }
                .buttonStyle(.pill(.secondary))
                .disabled(isDone)
                if isLogged {
                    Label("건강 앱에 기록했어요", systemImage: "heart.fill")
                        .font(.nunito(.subheadline, .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(isDone ? "완료" : "세트 \(run.set)/\(run.plan.sets)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("끝내기", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("건너뛰기") { run.skip() }
                        .disabled(isDone)
                }
            }
            .bottomAction {
                if isDone {
                    Button("닫기") { dismiss() }
                } else {
                    Button(run.isPaused ? "계속" : "일시정지") { run.togglePause() }
                }
            }
        }
        .task {
            while !Task.isCancelled {
                run.tick(.now)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        .sensoryFeedback(.impact(weight: .heavy), trigger: run.step) { _, _ in !isDone }
        .sensoryFeedback(.success, trigger: isDone) { _, done in done }
        .task(id: isDone) {
            // ponytail: 끝까지 마친 실행만 기록한다. 중간에 끝내도 남기려면 끝내기에서도 저장
            guard isDone, let workout else { return }
            isLogged = (try? await Health.save(workout, from: startedAt, to: .now)) != nil
        }
        // 운동 중에는 화면이 꺼지지 않게 한다
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var ring: some View {
        let seconds = Int(run.remaining.rounded(.up))
        let progress = isDone ? 1 : min(1, run.remaining / max(run.duration, 1))
        return ZStack {
            Circle().stroke(Theme.fill, lineWidth: 16)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(isDone ? Theme.positive : Theme.accent, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 4) {
                Text(phaseName)
                    .font(.nunito(.title3, .bold))
                    .foregroundStyle(.secondary)
                Text(clock(seconds))
                    .font(.display(72))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.default, value: seconds)
            }
            .padding(32)
        }
        .frame(maxWidth: video == nil ? 300 : 220)
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .combine)
    }

    private var phaseName: LocalizedStringKey {
        switch run.phase {
        case .work: "운동"
        case .rest: "휴식"
        case .done: "수고했어요"
        }
    }
}

#Preview {
    RunView(plan: IntervalPlan(sets: 3, work: 20, rest: 10), video: VideoSource(string: "https://youtu.be/dQw4w9WgXcQ"))
}
