import AppKit
import Observation
import UserNotifications

/// 뽀모도로 타이머 상태와 동작. 메뉴 막대·툴바·미니 창이 모두 이 객체를 본다.
@Observable
final class PomodoroController {
    static let shared = PomodoroController()

    /// 연결된 작업 줄
    struct TaskLink {
        weak var editor: OutlineEditor?
        var lineID: Int
        var title: String
        var document: String?
    }

    private(set) var settings: PomodoroSettings
    private(set) var timer: PomodoroTimer
    private(set) var now = Date()
    private(set) var task: TaskLink?
    let log = PomodoroLog(url: GlobalConfig.shared.directory.appendingPathComponent("pomodoro-log.json"))
    /// 기록이 바뀔 때마다 늘어 통계 화면을 다시 그리게 한다
    private(set) var logVersion = 0

    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored let sound = PomodoroSound()
    @ObservationIgnored lazy var presenters = PomodoroPresenters(controller: self)
    @ObservationIgnored private var askedNotification = false

    static let presentationChanged = Notification.Name("PomodoroPresentationChanged")

    private init() {
        let s = PomodoroSettings.load()
        settings = s
        timer = PomodoroTimer(settings: s)
    }

    // MARK: 설정

    func update(_ change: (inout PomodoroSettings) -> Void) {
        var s = settings
        change(&s)
        guard s != settings else { return }
        let presentationChanged = s.showMenuBar != settings.showMenuBar || s.showToolbar != settings.showToolbar || s.showMiniWindow != settings.showMiniWindow
        settings = s
        s.save()
        timer.settings = s
        if s.notify { requestNotificationPermission() }
        updateSound()
        if presentationChanged { applyPresentation() }
    }

    func applyPresentation() {
        presenters.apply(settings)
        NotificationCenter.default.post(name: Self.presentationChanged, object: nil)
    }

    // MARK: 표시용 값

    var timeText: String {
        let t = Int(timer.displayTime(now: now).rounded(timer.isCountUp ? .down : .up))
        return String(format: "%02d:%02d", t / 60, t % 60)
    }

    var phaseTitle: String {
        switch timer.phase {
        case .focus: timer.isCountUp ? "집중 (카운트업)" : "집중"
        case .shortBreak: "짧은 휴식"
        case .longBreak: "긴 휴식"
        }
    }

    var progress: Double { timer.progress(now: now) }

    var stats: PomodoroStats {
        _ = logVersion
        return PomodoroStats(log.records, now: now)
    }

    /// 연결 작업의 "완료/예상" 뽀모도로
    var taskProgress: String? {
        guard let task, let editor = task.editor, let i = editor.line(withID: task.lineID) else { return nil }
        let line = editor.index[i]
        let done = line.tag("pomodoro")?.value.flatMap { Int($0) } ?? 0
        if let estimate = line.tag("estimate")?.value.flatMap({ Int($0) }) { return "\(done)/\(estimate)" }
        return done > 0 ? "\(done)" : nil
    }

    // MARK: 동작

    /// 시작·일시정지·계속. 집중을 새로 시작하면 앞쪽 문서의 커서 줄을 작업으로 연결한다.
    func toggle() {
        now = Date()
        if timer.isRunning {
            timer.pause(now: now)
        } else {
            if timer.phase == .focus, !timer.started { linkFrontTask() }
            timer.start(now: now)
            if settings.notify { requestNotificationPermission() }
        }
        changed()
    }

    func stop() {
        now = Date()
        let start = timer.phaseStart
        if let event = timer.stop(now: now) { handle(event, start: start) }
        changed()
    }

    func skipBreak() {
        now = Date()
        timer.skipBreak(now: now)
        changed()
    }

    private func linkFrontTask() {
        let controller = (NSApp.mainWindow?.windowController as? DocumentWindowController)
            ?? NSApp.orderedWindows.compactMap { $0.windowController as? DocumentWindowController }.first
        guard let controller else { task = nil; return }
        let editor = controller.editor
        let i = editor.cursorLine
        guard i < editor.index.count, !editor.index[i].isBlank else { task = nil; return }
        task = TaskLink(editor: editor, lineID: editor.index[i].id, title: editor.index.displayName(i, editor.text),
                        document: controller.document?.displayName)
    }

    private func changed() {
        updateTicker()
        updateSound()
        presenters.refresh()
    }

    private func updateTicker() {
        if timer.isRunning, ticker == nil {
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            RunLoop.main.add(t, forMode: .common)
            ticker = t
        } else if !timer.isRunning {
            ticker?.invalidate()
            ticker = nil
        }
    }

    private func tick() {
        now = Date()
        let start = timer.phaseStart
        if let event = timer.tick(now: now) {
            handle(event, start: start)
            changed()
        } else {
            presenters.refresh()
        }
    }

    private func updateSound() {
        let focusing = timer.isRunning && timer.phase == .focus
        sound.setNoise(focusing ? settings.noise : .none, volume: settings.noiseVolume)
    }

    /// 단계가 끝났을 때: 알람, 알림, 기록, 작업 태그.
    private func handle(_ event: PomodoroTimer.Event, start: Date?) {
        switch event {
        case let .focusFinished(duration):
            sound.playAlarm(settings.focusAlarm, volume: settings.alarmVolume)
            let record = PomodoroRecord(start: start ?? now.addingTimeInterval(-duration), end: now,
                                        minutes: duration * PomodoroSettings.timeScale / 60,
                                        task: task?.title, document: task?.document)
            log.append(record)
            logVersion += 1
            if let task, let editor = task.editor { editor.incrementTag("pomodoro", lineID: task.lineID) }
            notify(title: "뽀모도로가 끝났습니다.", body: settings.disableBreak ? "다음 뽀모도로를 시작하세요." : "하나의 뽀모도로가 끝났습니다. 휴식을 취하세요.")
        case .breakFinished:
            sound.playAlarm(settings.breakAlarm, volume: settings.alarmVolume)
            notify(title: "휴식 시간이 끝났습니다.", body: "휴식이 끝났습니다. 다음 일을 시작하세요.")
        }
    }

    // MARK: 알림

    private func requestNotificationPermission() {
        guard !askedNotification else { return }
        askedNotification = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(title: String, body: String) {
        guard settings.notify else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let t = task?.title { content.subtitle = t }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
