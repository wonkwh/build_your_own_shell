import Foundation
import Observation

/// 인터벌 설정. 시간은 초 단위
struct IntervalPlan: Equatable {
    var sets: Int
    var work: Int
    var rest: Int

    /// 마지막 세트 뒤에는 휴식이 없다
    var total: Int { sets * work + (sets - 1) * rest }
}

enum Phase { case work, rest, done }

/// 진행 중인 인터벌. `tick` 으로 받은 시각 기준이라 백그라운드에 다녀와도 밀린 구간을 따라잡는다
@MainActor @Observable
final class IntervalRun {
    let plan: IntervalPlan
    private(set) var set = 1
    private(set) var phase = Phase.work
    /// 구간이 바뀔 때마다 1 씩 는다. 햅틱 트리거
    private(set) var step = 0
    private(set) var now: Date
    /// 진행 중일 때 현재 구간이 끝나는 시각
    private var end: Date?
    /// 멈춰 있을 때 남은 초
    private var paused: TimeInterval?

    init(plan: IntervalPlan, now: Date = .now) {
        self.plan = plan
        self.now = now
        end = now.addingTimeInterval(TimeInterval(plan.work))
    }

    var isPaused: Bool { paused != nil }

    var duration: TimeInterval {
        switch phase {
        case .work: TimeInterval(plan.work)
        case .rest: TimeInterval(plan.rest)
        case .done: 0
        }
    }

    var remaining: TimeInterval { paused ?? max(0, (end ?? now).timeIntervalSince(now)) }

    func tick(_ date: Date) {
        now = date
        while let end, now >= end { advance(from: end) }
    }

    func skip() {
        advance(from: now)
    }

    /// 현재 구간에 초를 더하거나 뺀다. 0 이하가 되면 다음 구간을 처음부터 시작한다
    func add(_ seconds: TimeInterval) {
        if remaining + seconds <= 0 { return skip() }
        if let paused {
            self.paused = paused + seconds
        } else {
            end = end?.addingTimeInterval(seconds)
        }
    }

    func togglePause() {
        if let paused {
            end = now.addingTimeInterval(paused)
            self.paused = nil
        } else if phase != .done {
            paused = remaining
            end = nil
        }
    }

    private func advance(from start: Date) {
        switch phase {
        case .work where set < plan.sets && plan.rest > 0:
            phase = .rest
        case .work where set < plan.sets, .rest:
            set += 1
            phase = .work
        case .work, .done:
            phase = .done
            end = nil
            paused = nil
            step += 1
            return
        }
        step += 1
        if paused != nil {
            paused = duration
        } else {
            end = start.addingTimeInterval(duration)
        }
    }
}
