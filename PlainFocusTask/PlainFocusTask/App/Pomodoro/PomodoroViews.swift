import Charts
import SwiftUI

/// 뽀모도로 타이머 화면. 팝오버(regular)·미니 창(compact)·전체 화면(large)에서 함께 쓴다.
struct PomodoroView: View {
    enum Style { case regular, compact, large }
    var style: Style = .regular
    private var c: PomodoroController { .shared }

    private var tint: Color { c.timer.phase.isBreak ? .green : Color(red: 0.93, green: 0.33, blue: 0.27) }
    private var ringSize: CGFloat { style == .large ? 380 : style == .compact ? 120 : 190 }
    private var timeFont: Font { .system(size: style == .large ? 96 : style == .compact ? 30 : 46, weight: .light, design: .rounded).monospacedDigit() }

    var body: some View {
        VStack(spacing: style == .compact ? 8 : 14) {
            Text(c.phaseTitle).font(style == .large ? .title : .headline).foregroundStyle(tint)
            ZStack {
                Circle().stroke(tint.opacity(0.15), lineWidth: style == .large ? 14 : 8)
                Circle().trim(from: 0, to: c.timer.isCountUp ? 1 : c.progress)
                    .stroke(tint, style: StrokeStyle(lineWidth: style == .large ? 14 : 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.3), value: c.progress)
                Text(c.timeText).font(timeFont)
            }
            .frame(width: ringSize, height: ringSize)
            taskLine
            controls
            if style != .compact { footer }
        }
        .padding(style == .large ? 40 : style == .compact ? 12 : 20)
    }

    private var taskLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
            Text(c.task?.title ?? "지정된 작업 없음").lineLimit(1).truncationMode(.tail)
            if let p = c.taskProgress { Text("🍅 \(p)").foregroundStyle(.secondary).monospacedDigit() }
        }
        .font(style == .large ? .title2 : .callout)
        .frame(maxWidth: style == .large ? 600 : 260)
    }

    @ViewBuilder private var controls: some View {
        HStack(spacing: 10) {
            if !c.timer.started {
                button(c.timer.phase.isBreak ? "휴식 시작" : "집중 시작", "play.fill", prominent: true) { c.toggle() }
                if c.timer.phase.isBreak { button("건너뛰기", "forward.end.fill") { c.skipBreak() } }
            } else {
                button(c.timer.isRunning ? "일시정지" : "계속", c.timer.isRunning ? "pause.fill" : "play.fill", prominent: true) { c.toggle() }
                button(c.timer.isCountUp ? "완료" : "정지", "stop.fill") { c.stop() }
                if c.timer.phase.isBreak { button("건너뛰기", "forward.end.fill") { c.skipBreak() } }
            }
        }
        .controlSize(style == .large ? .extraLarge : style == .compact ? .small : .large)
    }

    private func button(_ title: String, _ symbol: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: symbol) }
            .buttonStyle(.borderedProminent)
            .tint(prominent ? tint : .gray)
    }

    private var footer: some View {
        let s = c.stats
        return Text("오늘 🍅 \(s.todayCount) · \(Self.duration(s.todayMinutes)) / 목표 \(Self.duration(Double(c.settings.dailyGoalMinutes)))")
            .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
    }

    static func duration(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return m >= 60 ? "\(m / 60)시간 \(m % 60)분" : "\(m)분"
    }
}

/// 툴바의 남은 시간 버튼. 누르면 타이머 팝오버가 열린다.
struct PomodoroToolbarButton: View {
    @State private var showing = false
    private var c: PomodoroController { .shared }

    var body: some View {
        Button { showing.toggle() } label: {
            Label(c.timer.started ? c.timeText : "🍅", systemImage: c.timer.phase.isBreak ? "cup.and.saucer" : "timer")
                .labelStyle(.titleAndIcon)
                .monospacedDigit()
        }
        .help("뽀모도로")
        .popover(isPresented: $showing, arrowEdge: .bottom) { PomodoroView() }
    }
}

/// 통계 보고서
struct PomodoroStatsView: View {
    private var c: PomodoroController { .shared }

    var body: some View {
        let s = c.stats
        let daily = PomodoroStats.daily(c.log.records, days: 14, now: c.now)
        let goal = Double(c.settings.dailyGoalMinutes)
        let today = Calendar.current.startOfDay(for: c.now)
        let todayRecords = c.log.records.filter { $0.end >= today }.reversed()
        let achieved = daily.filter { $0.minutes >= goal && goal > 0 }.count
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    card("오늘", s.todayCount, s.todayMinutes)
                    card("이번 주", s.weekCount, s.weekMinutes)
                    card("전체", s.totalCount, s.totalMinutes)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("집중한 시간 (최근 14일)").font(.headline)
                    Text("목표 \(PomodoroView.duration(goal)) · 목표를 이룬 날 \(achieved)일").font(.caption).foregroundStyle(.secondary)
                    Chart {
                        ForEach(daily, id: \.day) { d in
                            BarMark(x: .value("날짜", d.day, unit: .day), y: .value("분", d.minutes))
                                .foregroundStyle(d.minutes >= goal ? Color.green : Color.red.opacity(0.75))
                        }
                        if goal > 0 { RuleMark(y: .value("목표", goal)).lineStyle(StrokeStyle(dash: [4])).foregroundStyle(.secondary) }
                    }
                    .chartXAxis { AxisMarks(values: .stride(by: .day, count: 2)) { _ in AxisValueLabel(format: .dateTime.month(.defaultDigits).day()) } }
                    .frame(height: 200)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("오늘의 집중 기록").font(.headline)
                    if todayRecords.isEmpty { Text("아직 없습니다.").foregroundStyle(.secondary) }
                    ForEach(Array(todayRecords.enumerated()), id: \.offset) { _, r in
                        HStack {
                            Text(r.start, format: .dateTime.hour().minute()).monospacedDigit().foregroundStyle(.secondary)
                            Text(r.task ?? "지정된 작업 없음").lineLimit(1)
                            Spacer()
                            Text(PomodoroView.duration(r.minutes)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(20)
        }
        .frame(minWidth: 460, minHeight: 480)
    }

    private func card(_ title: String, _ count: Int, _ minutes: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("🍅 \(count)").font(.title2.bold()).monospacedDigit()
            Text(PomodoroView.duration(minutes)).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// 설정 > 뽀모도로 탭
struct PomodoroSettingsView: View {
    private var c: PomodoroController { .shared }

    private func bind<T>(_ key: WritableKeyPath<PomodoroSettings, T>) -> Binding<T> {
        Binding(get: { c.settings[keyPath: key] }, set: { v in c.update { $0[keyPath: key] = v } })
    }

    var body: some View {
        Form {
            Section("시간") {
                Stepper("뽀모도로 시간 \(c.settings.focusMinutes)분", value: bind(\.focusMinutes), in: 1...120)
                Stepper("짧은 휴식 시간 \(c.settings.shortBreakMinutes)분", value: bind(\.shortBreakMinutes), in: 1...60)
                Stepper("긴 휴식 시간 \(c.settings.longBreakMinutes)분", value: bind(\.longBreakMinutes), in: 1...60)
                Stepper("긴 휴식 시간 간격 \(c.settings.longBreakInterval)뽀모도로", value: bind(\.longBreakInterval), in: 1...10)
                Stepper("하루 목표 \(PomodoroView.duration(Double(c.settings.dailyGoalMinutes)))", value: bind(\.dailyGoalMinutes), in: 0...720, step: 15)
            }
            Section("동작") {
                Toggle("자동으로 휴식 시작", isOn: bind(\.autoStartBreak))
                Toggle("자동으로 다음 뽀모도로 시작", isOn: bind(\.autoStartFocus))
                Toggle("휴식 금지", isOn: bind(\.disableBreak))
                Picker("타이머 모드", selection: bind(\.mode)) {
                    Text("카운트다운").tag(PomodoroSettings.Mode.countdown)
                    Text("카운트업 (00:00부터 재고 직접 멈춤)").tag(PomodoroSettings.Mode.countUp)
                }
            }
            Section("소리") {
                Picker("뽀모도로 종료 알람", selection: bind(\.focusAlarm)) {
                    ForEach(PomodoroSound.alarmNames, id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: c.settings.focusAlarm) { _, v in c.sound.playAlarm(v, volume: c.settings.alarmVolume) }
                Picker("휴식 종료 알람", selection: bind(\.breakAlarm)) {
                    ForEach(PomodoroSound.alarmNames, id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: c.settings.breakAlarm) { _, v in c.sound.playAlarm(v, volume: c.settings.alarmVolume) }
                Slider(value: bind(\.alarmVolume), in: 0...1) { Text("알람 볼륨") }
                Picker("화이트 노이즈", selection: bind(\.noise)) {
                    Text("없음").tag(PomodoroSettings.Noise.none)
                    Text("화이트 노이즈").tag(PomodoroSettings.Noise.white)
                    Text("핑크 노이즈").tag(PomodoroSettings.Noise.pink)
                    Text("브라운 노이즈").tag(PomodoroSettings.Noise.brown)
                    Text("똑딱똑딱 소리").tag(PomodoroSettings.Noise.ticking)
                }
                Slider(value: bind(\.noiseVolume), in: 0...1) { Text("화이트 노이즈 볼륨") }
                Toggle("끝나면 알림 센터로 알림", isOn: bind(\.notify))
            }
            Section("타이머 표시 위치") {
                Toggle("메뉴 막대", isOn: bind(\.showMenuBar))
                Toggle("문서 창 툴바", isOn: bind(\.showToolbar))
                Toggle("미니 플로팅 창", isOn: bind(\.showMiniWindow))
            }
        }
        .formStyle(.grouped)
    }
}
