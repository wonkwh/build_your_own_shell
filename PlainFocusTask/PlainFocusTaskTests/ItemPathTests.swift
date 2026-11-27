import Foundation
import Testing

/// item-path-spec.coffee 의 고정 문서
private let fixture = """
one
\ttwo
\t\tthree @t
\t\tfour @t
\tfive
\t\tsix @t(23)
"""

private func q(_ query: String, _ text: String = fixture, context: Int = -1) -> [String] {
    let ns = text as NSString
    let idx = LineIndex(ns)
    let path = ItemPath(query)
    return path.evaluate(idx, ns, context: context, now: Date(timeIntervalSince1970: 1_800_000_000)).map { idx.body($0, ns).components(separatedBy: " @")[0] }
}

@Suite struct ItemPathTests {
    @Test func simpleAndSets() {
        #expect(q("/one") == ["one"])
        #expect(q("//one union //e") == ["one", "three", "five"])
        #expect(q("/* union //two") == ["one", "two"])
        #expect(q("//three intersect //@t") == ["three"])
        #expect(q("//* except //@t") == ["one", "two", "five"])
        #expect(q("(//three except //two)") == ["three"])
        #expect(q("(//cantfindme except //two)") == [])
        #expect(q("(//one union //two union //three except //two)") == ["one", "two", "three"])
        #expect(q("((//one union //two union //three) except //two)") == ["one", "three"])
        #expect(q("(//@t)[0]") == ["three"])
        #expect(q("(//@t union //e)[0]") == ["one"])
    }

    @Test func locations() {
        #expect(q("one") == ["one"])
        #expect(q("one", context: 3) == [])
        #expect(q("/one", context: 3) == ["one"])
        #expect(q("//one", context: 3) == ["one"])
    }

    @Test func axes() {
        #expect(ItemPath("/ancestor-or-self::").error != nil)
        #expect(q("ancestor-or-self::*", context: 2) == ["one", "two", "three"])
        #expect(q("ancestor::*", context: 2) == ["one", "two"])
        #expect(q("//one or two/ancestor::*", context: 2) == ["one"])
        #expect(q("/descendant::one or two/descendant::*", context: 2) == ["two", "three", "four", "five", "six"])
        #expect(q("*", context: 1) == ["three", "four"])
        #expect(q("child::*", context: 1) == ["three", "four"])
        #expect(q("descendant-or-self::*", context: 1) == ["two", "three", "four"])
        #expect(q("/one//*") == ["two", "three", "four", "five", "six"])
        #expect(q("/one/descendant::*") == ["two", "three", "four", "five", "six"])
        #expect(q("/one///*") == ["one", "two", "three", "four", "five", "six"])
        #expect(q("/one/two/following-sibling::*") == ["five"])
        #expect(q("/one/two/following::*") == ["three", "four", "five", "six"])
        #expect(q("..*", context: 1) == ["one"])
        #expect(q("parent::*", context: 1) == ["one"])
        #expect(q("/one/five/preceding-sibling::*") == ["two"])
        #expect(q("/one/five/preceding::*") == ["one", "two", "three", "four"])
        #expect(q("/one/five/self::*") == ["five"])
    }

    @Test func predicates() {
        #expect(q("//count(*) = 0") == ["three", "four", "six"])
        #expect(q("//@text = \"one\"[0]") == ["one"])
        #expect(q("//@text = \"oNe\"") == ["one"])
        #expect(q("//@text one") == ["one"])
        #expect(q("//one") == ["one"])
        #expect(q("//= one") == ["one"])
        #expect(q("//@t 23") == ["six"])
        #expect(q("//@t") == ["three", "four", "six"])
        #expect(q("//w and o") == ["two"])
        #expect(q("//w or i") == ["two", "five", "six"])
        #expect(q("//not e") == ["two", "four", "six"])
        #expect(q("/one/not two") == ["five"])
        #expect(q("/one/not not two") == ["two"])
        #expect(q("/one/not not not two") == ["five"])
        #expect(q("//(@text e and not @t) or @t = 23") == ["one", "five", "six"])
        #expect(q("//e and @t or not @t") == ["one", "two", "three", "five"])
        #expect(q("//e and (@t or not v)") == ["one", "three"])
        #expect(ItemPath("(a and b) and c").error == nil)
        #expect(q("//((not @t))") == ["one", "two", "five"])
        #expect(q("//(((not @t)) or @t = 23)") == ["one", "two", "five", "six"])
        #expect(q("//not (@t or e)") == ["two"])
        #expect(q("//\"\"") == ["one", "two", "three", "four", "five", "six"])
    }

    @Test func relations() {
        #expect(q("//@t = \"\"") == ["three", "four"])
        #expect(q("//@t != 23") == ["one", "two", "three", "four", "five"])
        #expect(q("//@t < 23") == ["three", "four"])
        #expect(q("//@t <= 23") == ["three", "four", "six"])
        #expect(q("//@t > 09") == ["six"])
        #expect(q("//beginswith o") == ["one"])
        #expect(q("//contains ne") == ["one"])
        #expect(q("//endswith ne") == ["one"])
        #expect(q("//matches \".*i.*\"") == ["five", "six"])
        #expect(q("//@text matches \" @\\\\w(\"") == [])
    }

    @Test func modifiers() {
        #expect(q("@text contains insensitive", "Being all INSENSITIVE") == ["Being all INSENSITIVE"])
        #expect(q("@text contains [s] insensitive", "Being all INSENSITIVE") == [])
        #expect(q("[s] INSENSITIVE", "INSENSITIVE") == ["INSENSITIVE"])
        #expect(q("= [s] insensitive", "INSENSITIVE") == [])
        #expect(q("@text = 1.0", "1.0") == ["1.0"])
        #expect(q("@text = 1", "1.0") == [])
        #expect(q("@text = [n] 1", "1.0") == ["1.0"])
        #expect(q("@text contains[n] 1.0") == [])
        #expect(q("@text matches[n] 1.0") == [])
        #expect(q("@text =[b] true", "true") == ["true"])
        #expect(q("@text = 2012-11-1", "2012-11-01") == [])
        #expect(q("@text = [d] 2012-11-1", "2012-11-01") == ["2012-11-01"])
        #expect(q("@due = [d] tomorrow 2pm +1s -1s", "x @due(tomorrow 2pm)") == ["x"])
        #expect(q("@due = [d] tomorrow 2pm + 1s", "x @due(tomorrow 2pm)") == [])
        #expect(q("@text = a,b , c", "a, b, c") == [])
        #expect(q("@text = [l] a,b , c", "a, b, c") == ["a, b, c"])
        #expect(q("@text beginswith [l] a,b", "a, b, c") == ["a, b, c"])
        #expect(q("@text contains [l] c,a", "a, b, c") == ["a, b, c"])
        #expect(q("@text endswith [l] b,c", "a, b, c") == ["a, b, c"])
        let nums = "0.1, 20    , 07.0"
        #expect(q("@text = [nl] 0.1,020,7", nums) == [nums])
        #expect(q("@text < [nl] 0.11", nums) == [nums])
        #expect(q("@text < [nl] 0.1", nums) == [])
        #expect(q("@text < [nl] 0.11,0", nums) == [])
        #expect(q("@text matches[l] 7", nums) == [nums])
        #expect(q("@text matches[l] ^7", nums) == [])
        #expect(q("@text matches[l] ^2,7", nums) == [nums])
    }

    @Test func values() {
        #expect(q("find this string", "find this string") == ["find this string"])
        #expect(q("notandor", "notandor") == ["notandor"])
        #expect(q("//one is here or two is here", "one is here\ntwo is here") == ["one is here", "two is here"])
        #expect(q("//\"one is here or two is here\"", "one is here\none is here or two is here") == ["one is here or two is here"])
        #expect(q("0", "0one") == ["0one"])
        #expect(q("0one", "0one") == ["0one"])
        #expect(q("//@t1 = v1", "x @t1(v1)") == ["x"])
        #expect(q("//find a ü", "find a ü") == ["find a ü"])
        #expect(q("//찾기 한글", "할 일 찾기 한글") == ["할 일 찾기 한글"])
        #expect(q("/////union") == [])
    }

    @Test func slicing() {
        #expect(q("//@t[0]") == ["three"])
        #expect(q("//@t[1]") == ["four"])
        #expect(q("//@t[300]") == ["six"])
        #expect(q("//@t[-1]") == ["six"])
        #expect(q("//@t[-3]") == ["three"])
        #expect(q("//@t[-300]") == ["three"])
        #expect(q("//@t[0:2]") == ["three", "four"])
        #expect(q("//@t[0:300]") == ["three", "four", "six"])
        #expect(q("//@t[0:-1]") == ["three", "four"])
        #expect(q("//@t[0:-3]") == [])
        #expect(q("//@t[0:]") == ["three", "four", "six"])
    }

    @Test func typesAndTaskPaperSearches() {
        let doc = "Inbox:\n\t- a @today\n\t- b @done\n\t\t- c\nWork:\n\t- d @due(2000-01-01)\n\tnote"
        #expect(q("project *", doc) == ["Inbox:", "Work:"])
        #expect(q("task", doc) == ["- a", "- b", "- c", "- d"])
        #expect(q("project Work//task", doc) == ["- d"])
        #expect(q("not @done except @done//*", doc) == ["Inbox:", "- a", "Work:", "- d", "note"])
        #expect(q("@today union @due <[d] tomorrow", doc) == ["- a", "- d"])
        #expect(q("//@type = note", doc) == ["note"])
    }

    @Test func notDoneExceptPerformanceShape() {
        // item-path-spec 의 성능 사례: 깊이 4, 너비 5, 깊이 2 항목에 @done
        var lines: [String] = []
        func build(_ depth: Int, _ level: Int) {
            for _ in 0...4 {
                lines.append(String(repeating: "\t", count: level) + "hello" + (depth == 2 ? " @done" : ""))
                if depth > 0 { build(depth - 1, level + 1) }
            }
        }
        build(4, 0)
        #expect(q("not @done except @done//*", lines.joined(separator: "\n")).count == 30)
    }
}
