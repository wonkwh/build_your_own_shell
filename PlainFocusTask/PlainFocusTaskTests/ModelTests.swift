import Foundation
import Testing

/// 부분 갱신과 전체 파싱 비교용 요약
private func signature(_ index: LineIndex) -> [String] {
    index.lines.map { l in
        "\(l.start),\(l.length),\(l.terminator),\(l.level),\(l.type),\(l.depth),\(l.parent),\(l.branchEnd),\(l.previousSibling),\(l.contentEnd),"
            + l.tags.map { "\($0.name)=\($0.value ?? "nil")@\($0.range.location)" }.joined(separator: ";")
    }
}

/// 재현 가능한 난수
struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

@Suite struct LineIndexTests {
    @Test func types() {
        let idx = LineIndex("Inbox:\n- task @done\nnote\nP: @a(1)\nP: \n- x:\n-not task\n@only" as NSString)
        #expect(idx.lines.map(\.type) == [.project, .task, .note, .project, .note, .task, .note, .note])
    }

    @Test func tags() {
        let text = "- a @due(2026-11-27) @x(a\\(b\\)) b@c @today" as NSString
        let idx = LineIndex(text)
        let tags = idx[0].tags
        #expect(tags.map(\.name) == ["due", "x", "today"])
        #expect(tags.map(\.value) == ["2026-11-27", "a(b)", nil])
        #expect(text.substring(with: tags[0].range) == "@due(2026-11-27)")
        #expect(idx[0].contentEnd == ("- a @due(2026-11-27) @x(a\\(b\\)) b@c" as NSString).length)
    }

    @Test func trailingTags() {
        let text = "\tProject: @a @b(1)  " as NSString
        let idx = LineIndex(text)
        #expect(idx[0].type == .project)
        #expect(idx[0].contentEnd == ("\tProject:" as NSString).length)
        #expect(idx.displayName(0, text) == "Project")
    }

    @Test func structure() {
        let idx = LineIndex("A:\n\t- b\n\t\tc\n\n\t- d\nE:" as NSString)
        #expect(idx.lines.map(\.level) == [0, 1, 2, 0, 1, 0])
        #expect(idx.lines.map(\.depth) == [0, 1, 2, 1, 1, 0])
        #expect(idx.lines.map(\.parent) == [-1, 0, 1, 0, 0, -1])
        #expect(idx.lines.map(\.branchEnd) == [5, 3, 3, 4, 5, 6])
        #expect(idx.children(-1) == [0, 5])
        #expect(idx.children(0) == [1, 3, 4])
        #expect(idx.previousSibling(4) == 3)
        #expect(idx.nextSibling(1) == 3)
    }

    @Test func spacesAndCRLF() {
        let idx = LineIndex("A\r\n    b\r\n  c" as NSString)
        #expect(idx.lines.map(\.level) == [0, 1, 0])
        #expect(idx.lines.map(\.terminator) == [2, 2, 0])
        #expect(idx.lines.map(\.length) == [1, 5, 3])
    }

    @Test func lineAtLocation() {
        let idx = LineIndex("ab\ncd\n" as NSString)
        #expect(idx.count == 3)
        #expect([0, 2, 3, 5, 6].map { idx.line(at: $0) } == [0, 0, 1, 1, 2])
    }

    @Test func incrementalMatchesFull() {
        var rng = SplitMix(state: 42)
        let pieces = ["\n", "\t", "- ", "@done", ":", "a", " @x(1)", "\r\n", "Proj:\n\t- t\n", "  ", "(", ")"]
        let text = NSMutableString(string: "Inbox:\n\t- one @today\n\t\tnote\nTwo:\n")
        let idx = LineIndex(text)
        for _ in 0..<2000 {
            let loc = Int.random(in: 0...text.length, using: &rng)
            if Bool.random(using: &rng) || text.length == 0 {
                let s = pieces.randomElement(using: &rng)!
                text.insert(s, at: loc)
                idx.update(text, editedRange: NSRange(location: loc, length: (s as NSString).length), delta: (s as NSString).length)
            } else {
                let len = min(Int.random(in: 1...4, using: &rng), text.length - loc)
                text.deleteCharacters(in: NSRange(location: loc, length: len))
                idx.update(text, editedRange: NSRange(location: loc, length: 0), delta: -len)
            }
            #expect(signature(idx) == signature(LineIndex(text)))
        }
    }
}

@Suite struct DateParserTests {
    // 2026-11-27(금) 10:30 기준
    let now = DateParser.calendar.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: 10, minute: 30))!

    func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 0, _ min: Int = 0, _ s: Int = 0) -> Date {
        DateParser.calendar.date(from: DateComponents(year: y, month: m, day: day, hour: h, minute: min, second: s))!
    }

    func p(_ s: String) -> Date? { DateParser.parse(s, now: now) }

    @Test func absolute() {
        #expect(p("1976-11-27") == d(1976, 11, 27))
        #expect(p("1976-11") == d(1976, 11, 1))
        #expect(p("2012") == d(2012, 1, 1))
        #expect(p("1976-11-27 at 2pm +2s -1sec +2s") == d(1976, 11, 27, 14, 0, 3))
        #expect(p("1976-11-27 2pm +2s -1sec +2s") == d(1976, 11, 27, 14, 0, 3))
    }

    @Test func relative() {
        #expect(p("today") == d(2026, 11, 27))
        #expect(p("yesterday") == d(2026, 11, 26))
        #expect(p("tomorrow") == d(2026, 11, 28))
        #expect(p("now") == now)
        #expect(p("last year") == d(2025, 1, 1))
        #expect(p("last quarter") == d(2026, 7, 1))
        #expect(p("last month") == d(2026, 10, 1))
        #expect(p("last week") == d(2026, 11, 16))
        #expect(p("last day") == d(2026, 11, 26))
        #expect(p("this year") == d(2026, 1, 1))
        #expect(p("this quarter") == d(2026, 10, 1))
        #expect(p("this week") == d(2026, 11, 23))
        #expect(p("next Month") == d(2026, 12, 1))
        #expect(p("next week") == d(2026, 11, 30))
        #expect(p("next year") == d(2027, 1, 1))
    }

    @Test func named() {
        #expect(p("jul 7") == d(2026, 7, 7))
        #expect(p("JuLy 7") == d(2026, 7, 7))
        #expect(p("next JuLy 7") == d(2027, 7, 7))
        #expect(p("last JuLy 7") == d(2025, 7, 7))
        #expect(p("monday") == d(2026, 11, 23))
        #expect(p("mon") == d(2026, 11, 23))
        #expect(p("next mon") == d(2026, 11, 30))
        #expect(p("last mon") == d(2026, 11, 16))
        #expect(p("fri") == d(2026, 11, 27))
    }

    @Test func time() {
        #expect(p("2:15:32") == d(2026, 11, 27, 2, 15, 32))
        #expect(p("2:15:32 PM") == d(2026, 11, 27, 14, 15, 32))
        #expect(p("2 am") == d(2026, 11, 27, 2))
        #expect(p("2pm") == d(2026, 11, 27, 14))
        #expect(p("12pm") == d(2026, 11, 27, 12))
        #expect(p("this may 1 9pm") == d(2026, 5, 1, 21))
        #expect(p("this may at 9pm -10m") == d(2026, 5, 1, 20, 50))
    }

    @Test func durations() {
        #expect(p("3 s") == now.addingTimeInterval(3))
        #expect(p("3 m") == now.addingTimeInterval(180))
        #expect(p("3 h") == now.addingTimeInterval(3 * 3600))
        #expect(p("2d") == d(2026, 11, 29, 10, 30))
        #expect(p("+1w") == d(2026, 12, 4, 10, 30))
        #expect(p("- 3 years") == d(2023, 11, 27, 10, 30))
        #expect(p("4 o") == d(2027, 3, 27, 10, 30))
        #expect(p("1 q") == d(2027, 2, 27, 10, 30))
        #expect(p("2012 seconds") == now.addingTimeInterval(2012))
        #expect(p("2012s") == now.addingTimeInterval(2012))
    }

    @Test func invalid() {
        #expect(p("") == nil)
        #expect(p("banana") == nil)
        #expect(p("2") == d(2, 1, 1))
    }

    @Test func format() {
        #expect(DateParser.format(d(2016, 2, 1)) == "2016-02-01")
        #expect(DateParser.format(d(2016, 5, 1, 9)) == "2016-05-01 09:00")
    }
}
