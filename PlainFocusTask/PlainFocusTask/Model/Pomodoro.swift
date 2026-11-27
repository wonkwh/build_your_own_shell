import Foundation

/// 뽀모도로 단계
enum PomodoroPhase: String, Codable, Sendable {
    case focus, shortBreak, longBreak

    var isBreak: Bool { self != .focus }
}

/// Focus To-Do와 같은 뽀모도로 설정. `UserDefaults`에 JSON으로 둔다.
struct PomodoroSettings: Codable, Equatable, Sendable {
    enum Mode: String, Codable, CaseIterable, Sendable { case countdown, countUp }
    enum Noise: String, Codable, CaseIterable, Sendable { case none, white, pink, brown, ticking }

    var focusMinutes = 25
    var shortBreakMinutes = 5
    var longBreakMinutes = 15
    var longBreakInterval = 4
    var autoStartBreak = false
    var autoStartFocus = false
    var disableBreak = false
    var mode: Mode = .countdown
    var focusAlarm = "Glass"
    var breakAlarm = "Hero"
    var alarmVolume = 0.7
    var noise: Noise = .none
    var noiseVolume = 0.5
    var dailyGoalMinutes = 120
    var showMenuBar = true
    var showToolbar = true
    var showMiniWindow = false
    var notify = true

    static let defaultsKey = "pomodoroSettings"

    /// 디버그용 시간 배율. `-pomodoroTimeScale 60`이면 1분이 1초가 된다
    nonisolated(unsafe) static var timeScale: Double = {
        let v = UserDefaults.standard.double(forKey: "pomodoroTimeScale")
        return v > 0 ? v : 1
    }()

    func duration(_ phase: PomodoroPhase) -> TimeInterval {
        let minutes = switch phase {
        case .focus: focusMinutes
        case .shortBreak: shortBreakMinutes
        case .longBreak: longBreakMinutes
        }
        return TimeInterval(minutes) * 60 / Self.timeScale
    }

    /// 저장된 값에 없는 키는 기본값으로 채운다.
    static func load(_ defaults: UserDefaults = .standard) -> PomodoroSettings {
        guard let data = defaults.data(forKey: defaultsKey),
              let stored = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let base = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(PomodoroSettings())) as? [String: Any],
              let merged = try? JSONSerialization.data(withJSONObject: base.merging(stored) { $1 }),
              let settings = try? JSONDecoder().decode(PomodoroSettings.self, from: merged)
        else { return PomodoroSettings() }
        return settings
    }

    func save(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}

/// 뽀모도로 상태 기계. 시각을 인자로 받아 잠자기 뒤에도 남은 시간이 정확하다.
struct PomodoroTimer: Sendable {
    enum Event: Equatable, Sendable {
        /// 집중이 끝남. 실제 집중 시간(초)
        case focusFinished(TimeInterval)
        case breakFinished
    }

    var settings: PomodoroSettings
    /// 지금(또는 다음에 시작할) 단계
    private(set) var phase: PomodoroPhase = .focus
    /// 이 단계를 시작했는지. false면 시작 버튼을 기다린다
    private(set) var started = false
    private(set) var isRunning = false
    /// 이 단계를 처음 시작한 시각
    private(set) var phaseStart: Date?
    /// 마지막으로 다시 시작한 시각과 그 전까지 흐른 시간
    private var resumedAt: Date?
    private var elapsedBeforeResume: TimeInterval = 0
    private(set) var completedFocusCount = 0

    init(settings: PomodoroSettings) { self.settings = settings }

    var isCountUp: Bool { phase == .focus && settings.mode == .countUp }
    var totalDuration: TimeInterval { settings.duration(phase) }

    func elapsed(now: Date) -> TimeInterval {
        elapsedBeforeResume + (isRunning ? now.timeIntervalSince(resumedAt ?? now) : 0)
    }

    /// 카운트다운이면 남은 시간, 카운트업이면 흐른 시간
    func displayTime(now: Date) -> TimeInterval {
        isCountUp ? elapsed(now: now) : max(totalDuration - elapsed(now: now), 0)
    }

    func progress(now: Date) -> Double {
        guard !isCountUp, totalDuration > 0 else { return 0 }
        return min(elapsed(now: now) / totalDuration, 1)
    }

    /// 대기 중이면 이 단계를 시작하고, 일시정지 중이면 이어 간다.
    mutating func start(now: Date) {
        guard !isRunning else { return }
        if !started {
            started = true
            phaseStart = now
            elapsedBeforeResume = 0
        }
        isRunning = true
        resumedAt = now
    }

    mutating func pause(now: Date) {
        guard isRunning else { return }
        elapsedBeforeResume = elapsed(now: now)
        isRunning = false
        resumedAt = nil
    }

    /// 정지. 카운트업 집중은 1분 이상이면 완료로 기록하고, 아니면 버린다.
    mutating func stop(now: Date) -> Event? {
        if isCountUp, started, elapsed(now: now) >= 60 / PomodoroSettings.timeScale {
            return finish(now: now)
        }
        reset(to: .focus)
        return nil
    }

    /// 휴식을 건너뛰고 집중으로 간다.
    mutating func skipBreak(now: Date) {
        guard phase.isBreak else { return }
        reset(to: .focus)
        if settings.autoStartFocus { start(now: now) }
    }

    /// 1초마다 부른다. 카운트다운이 끝나면 다음 단계로 넘어가고 이벤트를 돌려준다.
    mutating func tick(now: Date) -> Event? {
        guard isRunning, !isCountUp, elapsed(now: now) >= totalDuration else { return nil }
        return finish(now: now)
    }

    private mutating func finish(now: Date) -> Event {
        let event: Event
        let next: PomodoroPhase
        let autoStart: Bool
        if phase == .focus {
            event = .focusFinished(isCountUp ? elapsed(now: now) : totalDuration)
            completedFocusCount += 1
            if settings.disableBreak {
                next = .focus
                autoStart = settings.autoStartFocus
            } else {
                next = completedFocusCount % max(settings.longBreakInterval, 1) == 0 ? .longBreak : .shortBreak
                autoStart = settings.autoStartBreak
            }
        } else {
            event = .breakFinished
            next = .focus
            autoStart = settings.autoStartFocus
        }
        reset(to: next)
        if autoStart { start(now: now) }
        return event
    }

    private mutating func reset(to phase: PomodoroPhase) {
        self.phase = phase
        started = false
        isRunning = false
        phaseStart = nil
        resumedAt = nil
        elapsedBeforeResume = 0
    }
}

/// 끝낸 뽀모도로 한 개
struct PomodoroRecord: Codable, Equatable, Sendable {
    var start: Date
    var end: Date
    var minutes: Double
    var task: String?
    var document: String?
}

/// 기록 집계. 날짜 경계는 주어진 달력을 따른다(주는 월요일 시작).
struct PomodoroStats: Equatable {
    var todayCount = 0, todayMinutes = 0.0
    var weekCount = 0, weekMinutes = 0.0
    var totalCount = 0, totalMinutes = 0.0

    init(_ records: [PomodoroRecord], now: Date, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let weekday = (calendar.component(.weekday, from: today) + 5) % 7
        let weekStart = calendar.date(byAdding: .day, value: -weekday, to: today)!
        for r in records {
            totalCount += 1
            totalMinutes += r.minutes
            if r.end >= weekStart { weekCount += 1; weekMinutes += r.minutes }
            if r.end >= today { todayCount += 1; todayMinutes += r.minutes }
        }
    }

    /// 최근 `days`일의 날짜별 집중 분. 오래된 날부터.
    static func daily(_ records: [PomodoroRecord], days: Int, now: Date, calendar: Calendar = .current) -> [(day: Date, minutes: Double)] {
        let today = calendar.startOfDay(for: now)
        var result = (0..<days).reversed().map { (day: calendar.date(byAdding: .day, value: -$0, to: today)!, minutes: 0.0) }
        for r in records {
            let day = calendar.startOfDay(for: r.end)
            if let k = result.firstIndex(where: { $0.day == day }) { result[k].minutes += r.minutes }
        }
        return result
    }
}

/// 기록 파일(JSON).
final class PomodoroLog {
    let url: URL
    private(set) var records: [PomodoroRecord] = []

    init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url) {
            records = (try? JSONDecoder().decode([PomodoroRecord].self, from: data)) ?? []
        }
    }

    func append(_ record: PomodoroRecord) {
        records.append(record)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(records).write(to: url, options: .atomic)
    }
}

extension LineText {
    /// 정수 값 태그를 1 늘린다. 없으면 1로 붙인다.
    static func incrementTag(_ s: String, _ name: String) -> String {
        let current = tags(s).first { $0.name == name }.flatMap { $0.value.flatMap { Int($0) } } ?? 0
        return setTag(s, name, String(current + 1))
    }
}
