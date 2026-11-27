import Foundation
import Testing

@Suite struct PomodoroTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    @Test func focusThenShortThenLongBreak() {
        var t = PomodoroTimer(settings: PomodoroSettings())
        var clock: TimeInterval = 0
        for round in 1...4 {
            t.start(now: at(clock))
            clock += 25 * 60
            #expect(t.tick(now: at(clock - 1)) == nil)
            #expect(t.tick(now: at(clock)) == .focusFinished(25 * 60))
            #expect(t.phase == (round == 4 ? .longBreak : .shortBreak))
            #expect(!t.started)
            t.start(now: at(clock))
            clock += t.totalDuration
            #expect(t.tick(now: at(clock)) == .breakFinished)
            #expect(t.phase == .focus)
        }
        #expect(t.completedFocusCount == 4)
    }

    @Test func autoStartAndDisableBreak() {
        var s = PomodoroSettings()
        s.autoStartBreak = true
        var t = PomodoroTimer(settings: s)
        t.start(now: at(0))
        _ = t.tick(now: at(1500))
        #expect(t.phase == .shortBreak && t.isRunning)
        _ = t.tick(now: at(1500 + 300))
        #expect(t.phase == .focus && !t.isRunning)

        s.disableBreak = true
        s.autoStartFocus = true
        var u = PomodoroTimer(settings: s)
        u.start(now: at(0))
        #expect(u.tick(now: at(1500)) == .focusFinished(1500))
        #expect(u.phase == .focus && u.isRunning)
        #expect(u.displayTime(now: at(1600)) == 1400)
    }

    @Test func pauseKeepsRemaining() {
        var t = PomodoroTimer(settings: PomodoroSettings())
        t.start(now: at(0))
        t.pause(now: at(600))
        #expect(t.displayTime(now: at(5000)) == 900)
        #expect(t.tick(now: at(5000)) == nil)
        t.start(now: at(5000))
        #expect(t.displayTime(now: at(5100)) == 800)
        #expect(t.tick(now: at(5900)) == .focusFinished(1500))
    }

    @Test func stopAndSkip() {
        var t = PomodoroTimer(settings: PomodoroSettings())
        t.start(now: at(0))
        #expect(t.stop(now: at(100)) == nil)
        #expect(t.phase == .focus && !t.started)
        t.start(now: at(0))
        _ = t.tick(now: at(1500))
        #expect(t.phase == .shortBreak)
        t.skipBreak(now: at(1500))
        #expect(t.phase == .focus && !t.isRunning)
    }

    @Test func countUpRecordsElapsedOnStop() {
        var s = PomodoroSettings()
        s.mode = .countUp
        var t = PomodoroTimer(settings: s)
        t.start(now: at(0))
        #expect(t.tick(now: at(99_999)) == nil)
        #expect(t.displayTime(now: at(42 * 60)) == 42 * 60)
        #expect(t.stop(now: at(42 * 60)) == .focusFinished(42 * 60))
        #expect(t.phase == .shortBreak)
        var u = PomodoroTimer(settings: s)
        u.start(now: at(0))
        #expect(u.stop(now: at(30)) == nil)
    }

    @Test func settingsFillMissingKeys() {
        let d = UserDefaults(suiteName: "pomodoro-test")!
        d.removePersistentDomain(forName: "pomodoro-test")
        d.set(try! JSONSerialization.data(withJSONObject: ["focusMinutes": 50]), forKey: PomodoroSettings.defaultsKey)
        let s = PomodoroSettings.load(d)
        #expect(s.focusMinutes == 50)
        #expect(s.longBreakInterval == 4)
    }

    @Test func stats() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
        // 2026-11-27(금) 15:00 KST
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: 15))!
        func rec(_ daysAgo: Int, _ minutes: Double) -> PomodoroRecord {
            let end = cal.date(byAdding: .day, value: -daysAgo, to: now)!
            return PomodoroRecord(start: end.addingTimeInterval(-minutes * 60), end: end, minutes: minutes)
        }
        let records = [rec(0, 25), rec(0, 25), rec(3, 25), rec(5, 50), rec(20, 25)]
        let s = PomodoroStats(records, now: now, calendar: cal)
        #expect(s.todayCount == 2 && s.todayMinutes == 50)
        #expect(s.weekCount == 3 && s.weekMinutes == 75)
        #expect(s.totalCount == 5 && s.totalMinutes == 150)
        let daily = PomodoroStats.daily(records, days: 14, now: now, calendar: cal)
        #expect(daily.count == 14)
        #expect(daily.last?.minutes == 50)
        #expect(daily[daily.count - 6].minutes == 50)
    }

    @Test func tagHelpers() {
        #expect(LineText.incrementTag("- a", "pomodoro") == "- a @pomodoro(1)")
        #expect(LineText.incrementTag("\t- a @pomodoro(2) @x", "pomodoro") == "\t- a @pomodoro(3) @x")
        #expect(LineText.setTag("- a", "estimate", "4") == "- a @estimate(4)")
    }

    @Test func logRoundTrip() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pomo-\(UUID()).json")
        let log = PomodoroLog(url: url)
        log.append(PomodoroRecord(start: at(0), end: at(1500), minutes: 25, task: "a", document: "d"))
        #expect(PomodoroLog(url: url).records.count == 1)
        try? FileManager.default.removeItem(at: url)
    }
}
