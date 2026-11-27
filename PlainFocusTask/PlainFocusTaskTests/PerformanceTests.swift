import Foundation
import Testing

/// 성능 목표(1만 줄): 열기 200ms, 입력 1ms, 질의 20ms. 디버그 빌드는 느리므로 실제 값은 Release로 잰다.
@Suite struct PerformanceTests {
    static let document: String = {
        var lines: [String] = []
        for p in 0..<850 {
            lines.append("Project \(p):")
            for t in 0..<6 {
                let tags = t % 3 == 0 ? " @done(2026-11-01)" : t % 3 == 1 ? " @today @due(2026-11-\(10 + t))" : ""
                lines.append("\t- 할 일 \(p)-\(t) 보고서 정리 https://example.com/\(t)\(tags)")
                if t % 2 == 0 { lines.append("\t\t메모 \(t) 세부 사항을 적어 둔다") }
            }
            lines.append("\tSub \(p):")
            lines.append("\t\t- 하위 작업 @priority(\(p % 5))")
        }
        return lines.joined(separator: "\n")
    }()

    static var limit: Double {
        #if DEBUG
        return 10
        #else
        return 1
        #endif
    }

    func ms(_ body: () -> Void) -> Double {
        let start = ContinuousClock.now
        body()
        let d = ContinuousClock.now - start
        return Double(d.components.attoseconds) / 1e15 + Double(d.components.seconds) * 1000
    }

    @Test func tenThousandLines() {
        let text = NSMutableString(string: Self.document)
        var index: LineIndex!
        let open = ms { index = LineIndex(text) }
        #expect(index.count >= 10_000)

        var typing: [Double] = []
        for k in 0..<200 {
            let loc = index[(k * 37) % index.count].end
            text.insert("a", at: loc)
            typing.append(ms { index.update(text, editedRange: NSRange(location: loc, length: 1), delta: 1) })
        }
        let typingAvg = typing.reduce(0, +) / Double(typing.count)

        var hidden: [Bool] = []
        let visibility = ms { hidden = Visibility(filterHiddenIDs: nil).hidden(index) }
        #expect(hidden.count == index.count)

        let queries = ["@today union @due <[d] tomorrow", "not @done except @done//*", "project *//task 보고서"]
        #expect(queries.allSatisfy { ItemPath($0).error == nil })
        let queryTimes = queries.map { q in ms { _ = ItemPath(q).evaluate(index, text) } }

        print("PERF lines=\(index.count) open=\(open)ms typing=\(typingAvg)ms visibility=\(visibility)ms queries=\(queryTimes)")
        #expect(open < 200 * Self.limit)
        #expect(typingAvg < 1 * Self.limit)
        #expect(queryTimes.allSatisfy { $0 < 20 * Self.limit })
    }
}
