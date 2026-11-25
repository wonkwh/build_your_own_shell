import SwiftUI

/// 실행 화면. Gymshark 휴식 시트처럼 큰 링 카운트다운, 건너뛰기, −10초 / +10초
struct RunView: View {
    let video: VideoSource?
    @State private var run: IntervalRun
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    init(plan: IntervalPlan, video: VideoSource? = nil) {
        self.video = video
        _run = State(initialValue: IntervalRun(plan: plan))
    }

    private var isDone: Bool { run.phase == .done }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                if let video {
                    // ponytail: 3단계에서 앱 안 플레이어로 바꾼다. 지금은 YouTube 앱·사파리로 연다
                    Button { openURL(video.url) } label: {
                        VideoThumbnail(source: video)
                            .overlay {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.white)
                                    .shadow(radius: 6)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("영상 열기")
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
