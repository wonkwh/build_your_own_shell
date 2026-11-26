import Foundation
import Testing
@testable import TubeTimer

@MainActor
struct IntervalRunTests {
    let start = Date(timeIntervalSince1970: 0)
    let plan = IntervalPlan(sets: 2, work: 10, rest: 5)

    @Test func totalSkipsLastRest() {
        #expect(plan.total == 25)
    }

    @Test func walksWorkRestWorkDone() {
        let run = IntervalRun(plan: plan, now: start)
        run.tick(start + 10)
        #expect((run.set, run.phase) == (1, .rest))
        run.tick(start + 15)
        #expect((run.set, run.phase) == (2, .work))
        run.tick(start + 25)
        #expect(run.phase == .done)
    }

    @Test func catchesUpAfterBackground() {
        let run = IntervalRun(plan: plan, now: start)
        run.tick(start + 12)
        #expect(run.phase == .rest)
        #expect(run.remaining == 3)
    }

    @Test func zeroRestGoesStraightToNextSet() {
        let run = IntervalRun(plan: IntervalPlan(sets: 2, work: 10, rest: 0), now: start)
        run.tick(start + 10)
        #expect((run.set, run.phase) == (2, .work))
    }

    @Test func addAndSubtractSeconds() {
        let run = IntervalRun(plan: plan, now: start)
        run.add(10)
        #expect(run.remaining == 20)
        run.add(-25)
        #expect(run.phase == .rest)
    }

    @Test func pauseFreezesAndSkipKeepsPaused() {
        let run = IntervalRun(plan: plan, now: start)
        run.tick(start + 4)
        run.togglePause()
        run.tick(start + 100)
        #expect(run.remaining == 6)
        run.skip()
        #expect(run.phase == .rest && run.isPaused && run.remaining == 5)
        run.togglePause()
        run.tick(start + 105)
        #expect((run.set, run.phase) == (2, .work))
    }

    @Test func upcomingChangesUntilDone() {
        let run = IntervalRun(plan: plan, now: start)
        run.tick(start + 3)
        let changes = run.upcomingChanges()
        #expect(changes.map(\.date) == [start + 10, start + 15, start + 25])
        #expect(changes.map(\.set) == [1, 2, 2])
        #expect(changes.map(\.phase) == [.rest, .work, .done])
        run.togglePause()
        #expect(run.upcomingChanges().isEmpty)
    }
}
