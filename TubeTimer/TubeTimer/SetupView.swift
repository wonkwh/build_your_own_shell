import SwiftData
import SwiftUI

/// 루틴 편집. 이름 · 타이머(Life Reset 세 항목 + Breathwrk·Opal 큰 − / +) · 영상 링크
struct SetupView: View {
    @Bindable var routine: Routine
    @State private var isRunning = false
    @Environment(\.modelContext) private var context

    private var plan: IntervalPlan { routine.plan }

    var body: some View {
        CardScroll {
            CardSection("이름") {
                TextField("이름", text: $routine.name)
                    .submitLabel(.done)
            }
            CardSection("타이머", footer: Text("총 \(clock(plan.total))")) {
                StepperRow(title: "세트", value: $routine.sets, range: 1...99) { "\($0)" }
                StepperRow(title: "운동", value: $routine.work, range: 5...3600, step: 5, format: clock)
                StepperRow(title: "휴식", value: $routine.rest, range: 0...3600, step: 5, format: clock)
            }
            VideoSection(routine: routine)
        }
        .scrollDismissesKeyboard(.interactively)
        // 자동 저장을 기다리다 앱이 종료되면 바꾼 값을 잃으므로 바로 저장한다
        .onChange(of: plan) { try? context.save() }
        .onChange(of: routine.name) { try? context.save() }
        .onChange(of: routine.videoURL) { try? context.save() }
        .onChange(of: routine.videoTitle) { try? context.save() }
        .navigationTitle(routine.name)
        .navigationBarTitleDisplayMode(.inline)
        .bottomAction {
            Button("시작") { isRunning = true }
        }
        .fullScreenCover(isPresented: $isRunning) {
            RunView(plan: plan, video: routine.video)
        }
    }
}

/// 영상 링크. 붙이기 전에는 입력칸 + 붙여넣기, 붙인 뒤에는 썸네일 · 제목 · 지우기
private struct VideoSection: View {
    @Bindable var routine: Routine
    @State private var draft = ""
    @State private var isInvalid = false

    var body: some View {
        CardSection("영상", footer: footer) {
            if let source = routine.video {
                VStack(alignment: .leading, spacing: 12) {
                    VideoThumbnail(source: source)
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(routine.videoTitle ?? String(localized: "영상"))
                                .font(.nunito(.headline))
                                .lineLimit(2)
                            Text(caption(source))
                                .font(.nunito(.footnote))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("지우기", role: .destructive) {
                            routine.videoURL = nil
                            routine.videoTitle = nil
                        }
                        .tint(Theme.caution)
                    }
                }
            } else {
                HStack {
                    TextField("YouTube · mp4 링크", text: $draft)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit { apply(draft) }
                    PasteButton(payloadType: String.self) { strings in
                        Task { @MainActor in apply(strings.first ?? "") }
                    }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.capsule)
                }
            }
        }
    }

    private var footer: Text? {
        isInvalid ? Text("YouTube 링크나 https 로 시작하는 mp4 링크만 붙일 수 있어요").foregroundStyle(Theme.caution) : nil
    }

    private func caption(_ source: VideoSource) -> String {
        switch source {
        case .youtube: "YouTube"
        case .file(let url): url.host() ?? ""
        }
    }

    private func apply(_ text: String) {
        guard let source = VideoSource(string: text) else {
            isInvalid = true
            return
        }
        isInvalid = false
        draft = ""
        routine.videoURL = source.url
        Task {
            guard let title = await source.fetchTitle() else { return }
            routine.videoTitle = title
            if routine.name == Routine.newName || routine.name.isEmpty { routine.name = title }
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
    NavigationStack {
        SetupView(routine: Routine())
    }
    .modelContainer(for: Routine.self, inMemory: true)
}
