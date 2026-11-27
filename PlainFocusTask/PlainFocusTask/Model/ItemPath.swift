import Foundation

/// TaskPaper 질의 언어(`item-path-parser.pegjs`, `item-path.coffee`)를 그대로 옮긴 파서·실행기.
struct ItemPath {
    enum KeywordKind: Sendable { case set, axis, boolean, relation, modifier, attribute, function, string }

    struct Keyword: Sendable {
        var range: NSRange
        var kind: KeywordKind
    }

    let source: String
    let expression: Expr?
    let error: String?
    let keywords: [Keyword]

    init(_ source: String) {
        self.source = source
        var p = Parser(s: Array(source.utf16))
        let e = p.itemPathExpression()
        if let e, p.pos == p.s.count {
            expression = e
            error = nil
        } else {
            expression = nil
            error = "질의 \(max(p.furthest, p.pos) + 1)번째 글자를 해석할 수 없습니다"
        }
        keywords = p.keywords
    }

    /// 질의에 맞는 줄 번호를 문서 순서로 돌려준다. 잘못된 질의는 빈 배열.
    func evaluate(_ index: LineIndex, _ text: NSString, context: Int = -1, now: Date = .now) -> [Int] {
        guard let expression else { return [] }
        let e = Evaluator(index: index, text: text, now: now)
        return e.evaluate(expression, context)
    }

    // MARK: - AST

    enum Axis: Sendable {
        case ancestorOrSelf, ancestor, child, descendantOrSelf, descendant, followingSibling, following, parent, precedingSibling, preceding, selfAxis
    }

    struct Slice: Sendable {
        var start: Int
        /// nil이면 한 항목만, Int.max면 끝까지
        var end: Int?
    }

    indirect enum Expr: Sendable {
        case union(Expr, Expr, Slice?)
        case intersect(Expr, Expr, Slice?)
        case except(Expr, Expr, Slice?)
        case path(Path, Slice?)

        func sliced(_ slice: Slice?) -> Expr {
            switch self {
            case let .union(a, b, _): .union(a, b, slice)
            case let .intersect(a, b, _): .intersect(a, b, slice)
            case let .except(a, b, _): .except(a, b, slice)
            case let .path(p, _): .path(p, slice)
            }
        }
    }

    struct Path: Sendable {
        var absolute: Bool
        var steps: [Step]
    }

    struct Step: Sendable {
        var axis: Axis
        var type: ItemType?
        var predicate: Predicate
        var slice: Slice?
    }

    indirect enum Predicate: Sendable {
        case any
        case and(Predicate, Predicate)
        case or(Predicate, Predicate)
        case not(Predicate)
        case compare(Comparison)
    }

    enum Relation: String, Sendable, CaseIterable {
        case beginswith, contains, endswith, matches
        case eq = "=", ne = "!=", le = "<=", ge = ">=", lt = "<", gt = ">"
    }

    struct Modifier: Sendable {
        var element: Character = "i"
        var list = false
    }

    enum Value: Sendable {
        case string(String)
        case attribute(String)
        case count(Expr)
    }

    final class Comparison: Sendable {
        let left: Value
        let relation: Relation?
        let modifier: Modifier
        let right: Value?
        init(left: Value, relation: Relation?, modifier: Modifier, right: Value?) {
            self.left = left
            self.relation = relation
            self.modifier = modifier
            self.right = right
        }
    }
}

// MARK: - 파서 (PEG 선택 순서를 그대로 따른다)

private let reservedWords: Set<String> = ["union", "except", "intersect", "and", "or", "not", "beginswith", "contains", "endswith", "like", "matches", "=", "!", "<", ">"]
private let unquotedPunct = Set("~`!#$%^&*+={}|\\;',.?-".utf16)

private func isWS(_ c: UInt16) -> Bool { c == 32 || c == 9 || c == 10 || c == 13 }

private func isNameStart(_ c: UInt16) -> Bool {
    switch c {
    case 58, 65...90, 95, 97...122, 0xC0...0xD6, 0xD8...0xF6, 0xF8...0x2FF, 0x370...0x37D, 0x37F...0x1FFF,
         0x200C...0x200D, 0x2070...0x218F, 0x2C00...0x2FEF, 0x3001...0xD7FF, 0xF900...0xFDCF, 0xFDF0...0xFFFD: true
    default: false
    }
}

private func isNameChar(_ c: UInt16) -> Bool {
    isNameStart(c) || c == 45 || c == 46 || (48...57).contains(c) || c == 0xB7 || (0x300...0x36F).contains(c) || (0x203F...0x2040).contains(c)
}

private struct Parser {
    let s: [UInt16]
    var pos = 0
    var furthest = 0
    var keywords: [ItemPath.Keyword] = []

    typealias Expr = ItemPath.Expr

    // MARK: 도구

    var atEnd: Bool { pos >= s.count }
    func peek(_ offset: Int = 0) -> UInt16? { pos + offset < s.count ? s[pos + offset] : nil }

    mutating func ws() { while let c = peek(), isWS(c) { pos += 1 } }

    mutating func lit(_ str: String) -> Bool {
        let u = Array(str.utf16)
        guard pos + u.count <= s.count, Array(s[pos..<pos + u.count]) == u else {
            furthest = max(furthest, pos)
            return false
        }
        pos += u.count
        return true
    }

    mutating func keyword(_ kind: ItemPath.KeywordKind, from start: Int) {
        keywords.append(.init(range: NSRange(location: start, length: pos - start), kind: kind))
    }

    /// 실패하면 위치와 키워드를 되돌린다.
    mutating func attempt<T>(_ body: (inout Parser) -> T?) -> T? {
        let save = pos, kw = keywords.count
        if let r = body(&self) { return r }
        pos = save
        keywords.removeSubrange(kw...)
        return nil
    }

    mutating func kwLit(_ str: String, _ kind: ItemPath.KeywordKind) -> Bool {
        let start = pos
        guard lit(str) else { return false }
        keyword(kind, from: start)
        return true
    }

    // MARK: 집합

    mutating func itemPathExpression() -> Expr? {
        guard let e = unionPaths() else { return nil }
        ws()
        return e
    }

    mutating func setChain(_ word: String, _ next: (inout Parser) -> Expr?, _ make: (Expr, Expr) -> Expr) -> Expr? {
        guard let left = next(&self) else { return nil }
        if let right = attempt({ p -> Expr? in
            p.ws()
            guard p.kwLit(word, .set) else { return nil }
            p.ws()
            return p.setChain(word, next, make)
        }) { return make(left, right) }
        return left
    }

    mutating func unionPaths() -> Expr? { setChain("union", { $0.exceptPaths() }) { .union($0, $1, nil) } }
    mutating func exceptPaths() -> Expr? { setChain("except", { $0.intersectPaths() }) { .except($0, $1, nil) } }
    mutating func intersectPaths() -> Expr? { setChain("intersect", { $0.pathExpression() }) { .intersect($0, $1, nil) } }

    mutating func pathExpression() -> Expr? {
        let grouped = attempt { p -> Expr? in
            // !OrPredicates: 술어로 읽히면 괄호 경로가 아니다
            var probe = p
            if probe.orPredicates() != nil { return nil }
            guard p.lit("(") else { return nil }
            p.ws()
            guard let e = p.unionPaths() else { return nil }
            p.ws()
            guard p.lit(")") else { return nil }
            return e.sliced(p.attempt { $0.slice() })
        }
        return grouped ?? itemPath()
    }

    // MARK: 경로

    mutating func itemPath() -> Expr? {
        attempt { p -> Expr? in
            let absStart = p.pos
            let absolute = p.lit("/")
            if absolute { p.keyword(.axis, from: absStart) }
            guard var first = p.pathStep() else { return nil }
            if !absolute, first.1 { first.0.axis = .descendant }
            var steps = [first.0]
            while let step = p.attempt({ q -> ItemPath.Step? in
                let st = q.pos
                guard q.lit("/") else { return nil }
                q.keyword(.axis, from: st)
                return q.pathStep()?.0
            }) { steps.append(step) }
            return .path(ItemPath.Path(absolute: absolute, steps: steps), nil)
        }
    }

    /// - Returns: 단계와 축이 생략됐는지 여부
    mutating func pathStep() -> (ItemPath.Step, Bool)? {
        attempt { p -> (ItemPath.Step, Bool)? in
            let axis = p.attempt { $0.pathStepAxis() }
            let type = p.attempt { $0.pathStepType() }
            let predicate = p.attempt { $0.orPredicates() }
            let slice = p.attempt { $0.slice() }
            guard type != nil || predicate != nil else { return nil }
            return (ItemPath.Step(axis: axis ?? .child, type: type, predicate: predicate ?? .any, slice: slice), axis == nil)
        }
    }

    static let axes: [(String, ItemPath.Axis)] = [
        ("ancestor-or-self::", .ancestorOrSelf), ("ancestor::", .ancestor), ("child::", .child),
        ("descendant-or-self::", .descendantOrSelf), ("descendant::", .descendant),
        ("following-sibling::", .followingSibling), ("following::", .following),
        ("preceding-sibling::", .precedingSibling), ("preceding::", .preceding),
        ("parent::", .parent), ("self::", .selfAxis),
        ("//", .descendantOrSelf), ("/", .descendant), ("..", .parent), (".", .child),
    ]

    mutating func pathStepAxis() -> ItemPath.Axis? {
        for (word, axis) in Self.axes where kwLit(word, .axis) { return axis }
        return nil
    }

    mutating func pathStepType() -> ItemType? {
        let start = pos
        guard let name = self.name(), let type = ItemType(rawValue: name) else { return nil }
        keyword(.axis, from: start)
        ws()
        return type
    }

    mutating func slice() -> ItemPath.Slice? {
        guard lit("["), let start = integer() else { return nil }
        var end: Int?
        if lit(":") { end = attempt { $0.integer() } ?? Int.max }
        guard lit("]") else { return nil }
        return .init(start: start, end: end)
    }

    mutating func integer() -> Int? {
        attempt { p -> Int? in
            let neg = p.lit("-")
            let start = p.pos
            while let c = p.peek(), (48...57).contains(c) { p.pos += 1 }
            guard p.pos > start, let n = Int(String(utf16CodeUnits: Array(p.s[start..<p.pos]), count: p.pos - start)) else { return nil }
            return neg ? -n : n
        }
    }

    // MARK: 술어

    mutating func orPredicates() -> ItemPath.Predicate? {
        guard let left = andPredicates() else { return nil }
        if let right = attempt({ p -> ItemPath.Predicate? in
            p.ws()
            guard p.kwLit("or", .boolean) else { return nil }
            p.ws()
            return p.orPredicates()
        }) { return .or(left, right) }
        return left
    }

    mutating func andPredicates() -> ItemPath.Predicate? {
        guard let left = notPredicate() else { return nil }
        if let right = attempt({ p -> ItemPath.Predicate? in
            p.ws()
            guard p.kwLit("and", .boolean) else { return nil }
            p.ws()
            return p.andPredicates()
        }) { return .and(left, right) }
        return left
    }

    mutating func notPredicate() -> ItemPath.Predicate? {
        attempt { p -> ItemPath.Predicate? in
            var nots = 0
            while p.attempt({ q -> Bool? in
                guard q.kwLit("not", .boolean), let c = q.peek(), isWS(c) else { return nil }
                q.ws()
                return true
            }) != nil { nots += 1 }
            guard let e = p.predicateExpression() else { return nil }
            return nots % 2 == 1 ? .not(e) : e
        }
    }

    mutating func predicateExpression() -> ItemPath.Predicate? {
        attempt { p -> ItemPath.Predicate? in
            guard p.lit("(") else { return nil }
            p.ws()
            guard let e = p.orPredicates() else { return nil }
            p.ws()
            return p.lit(")") ? e : nil
        } ?? comparisonPredicate()
    }

    mutating func comparisonPredicate() -> ItemPath.Predicate? {
        if lit("*") { return .any }
        return attempt { p -> ItemPath.Predicate? in
            let left = p.attempt { $0.predicateValue() }
            p.ws()
            let relation = p.attempt { $0.relation() }
            p.ws()
            let modifier = p.attempt { $0.modifier() } ?? ItemPath.Modifier()
            p.ws()
            let right = p.attempt { $0.predicateValue() }
            guard left != nil || right != nil else { return nil }
            let comparison: ItemPath.Comparison
            if relation == nil, right == nil, let left {
                if case .attribute = left {
                    comparison = .init(left: left, relation: nil, modifier: modifier, right: nil)
                } else {
                    comparison = .init(left: .attribute("text"), relation: .contains, modifier: modifier, right: left)
                }
            } else {
                comparison = .init(left: left ?? .attribute("text"), relation: relation ?? .contains, modifier: modifier, right: right)
            }
            return .compare(comparison)
        }
    }

    mutating func relation() -> ItemPath.Relation? {
        for word in ["beginswith", "contains", "endswith", "matches", "=", "!=", "<=", ">=", "<", ">"] where kwLit(word, .relation) {
            return ItemPath.Relation(rawValue: word)
        }
        return nil
    }

    mutating func modifier() -> ItemPath.Modifier? {
        let start = pos
        guard lit("[") else { return nil }
        var m = ItemPath.Modifier()
        if let c = peek(), let ch = Unicode.Scalar(c).map(Character.init), "sinbd".contains(ch) { m.element = ch; pos += 1 }
        if lit("l") { m.list = true }
        guard lit("]") else { return nil }
        keyword(.modifier, from: start)
        return m
    }

    mutating func predicateValue() -> ItemPath.Value? {
        attempt { $0.functionValue() } ?? attempt { p in p.stringValue().map { .string($0) } }
    }

    mutating func functionValue() -> ItemPath.Value? {
        let start = pos
        if lit("@") {
            var segments: [String] = []
            repeat {
                let segStart = pos
                while let c = peek(), c != 58, isNameChar(c) { pos += 1 }
                guard pos > segStart else { return nil }
                segments.append(String(utf16CodeUnits: Array(s[segStart..<pos]), count: pos - segStart))
            } while attempt({ p -> Bool? in p.lit(":") ? true : nil }) != nil
            keyword(.attribute, from: start)
            return .attribute(segments[0])
        }
        guard kwLit("count", .function), lit("("), let e = itemPathExpression(), lit(")") else { return nil }
        return .count(e)
    }

    mutating func name() -> String? {
        guard let c = peek(), isNameStart(c) else { return nil }
        let start = pos
        pos += 1
        while let c = peek(), isNameChar(c) { pos += 1 }
        return String(utf16CodeUnits: Array(s[start..<pos]), count: pos - start)
    }

    mutating func stringValue() -> String? {
        var result: [UInt16] = []
        var any = false
        while let piece = attempt({ p -> [UInt16]? in
            let a = p.pos
            p.ws()
            let lead = Array(p.s[a..<p.pos])
            let start = p.pos
            guard let str = p.attempt({ $0.quotedString() }) ?? p.attempt({ $0.unquotedString() }) else { return nil }
            p.keyword(.string, from: start)
            let b = p.pos
            p.ws()
            return lead + str + Array(p.s[b..<p.pos])
        }) {
            result += piece
            any = true
        }
        guard any else { return nil }
        return String(utf16CodeUnits: result, count: result.count).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    mutating func quotedString() -> [UInt16]? {
        guard lit("\"") else { return nil }
        var chars: [UInt16] = []
        while let c = peek() {
            if c == 34 { pos += 1; return chars }
            if c == 92 {
                guard let n = peek(1) else { return nil }
                let mapped: UInt16? = switch n {
                case 34: 34
                case 92: 92
                case 47: 47
                case 98: 8
                case 102: 12
                case 110: 10
                case 114: 13
                case 116: 9
                default: nil
                }
                guard let mapped else { return nil }
                chars.append(mapped)
                pos += 2
                continue
            }
            guard c > 0x1F, c != 0x7F else { return nil }
            chars.append(c)
            pos += 1
        }
        return nil
    }

    mutating func unquotedString() -> [UInt16]? {
        let start = pos
        guard let c = peek() else { return nil }
        if (48...57).contains(c) || unquotedPunct.contains(c) {
            pos += 1
        } else if name() == nil {
            return nil
        }
        let token = Array(s[start..<pos])
        if reservedWords.contains(String(utf16CodeUnits: token, count: token.count)) { return nil }
        return token
    }
}

// MARK: - 실행기

private enum Val {
    case str(String)
    case num(Double)
    case bool(Bool)
    case list([Val?])

    var text: String {
        switch self {
        case let .str(s): s
        case let .num(n): n.isNaN ? "NaN" : (n == n.rounded() && abs(n) < 1e15 ? String(Int(n)) : String(n))
        case let .bool(b): b ? "true" : "false"
        case let .list(l): l.map { $0?.text ?? "" }.joined(separator: ",")
        }
    }

    var number: Double {
        switch self {
        case let .num(n): n
        case let .str(s): s.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : Double(s.trimmingCharacters(in: .whitespaces)) ?? .nan
        case let .bool(b): b ? 1 : 0
        case .list: .nan
        }
    }
}

private func strictEqual(_ a: Val?, _ b: Val?) -> Bool {
    switch (a, b) {
    case let (.str(x)?, .str(y)?): x == y
    case let (.num(x)?, .num(y)?): x == y
    case let (.bool(x)?, .bool(y)?): x == y
    default: false
    }
}

/// JS 비교 연산 흉내. 문자열끼리는 사전순, 나머지는 숫자로 바꿔 비교한다.
private func jsCompare(_ a: Val?, _ b: Val?, _ op: ItemPath.Relation) -> Bool {
    guard let a, let b else { return false }
    if case let .str(x) = a, case let .str(y) = b {
        switch op {
        case .lt: return x < y
        case .gt: return x > y
        case .le: return x <= y
        default: return x >= y
        }
    }
    let x = a.number, y = b.number
    switch op {
    case .lt: return x < y
    case .gt: return x > y
    case .le: return x <= y
    default: return x >= y
    }
}

private func parseFloat(_ s: String) -> Double {
    Scanner(string: s).scanDouble() ?? .nan
}

private final class Evaluator {
    let index: LineIndex
    let text: NSString
    let now: Date
    var leftConstants: [ObjectIdentifier: Val?] = [:]
    var rightConstants: [ObjectIdentifier: Val?] = [:]
    var regexes: [ObjectIdentifier: [NSRegularExpression]] = [:]

    init(index: LineIndex, text: NSString, now: Date) {
        self.index = index
        self.text = text
        self.now = now
    }

    var count: Int { index.count }

    func evaluate(_ expr: ItemPath.Expr, _ item: Int) -> [Int] {
        var results: [Int]
        let slice: ItemPath.Slice?
        switch expr {
        case let .union(a, b, s):
            results = union(evaluate(a, item), evaluate(b, item))
            slice = s
        case let .intersect(a, b, s):
            let r2 = Set(evaluate(b, item))
            results = evaluate(a, item).filter { r2.contains($0) }
            slice = s
        case let .except(a, b, s):
            let r2 = Set(evaluate(b, item))
            results = evaluate(a, item).filter { !r2.contains($0) }
            slice = s
        case let .path(p, s):
            results = evaluatePath(p, item)
            slice = s
        }
        applySlice(slice, &results, from: 0)
        return results
    }

    func union(_ a: [Int], _ b: [Int]) -> [Int] {
        var r: [Int] = []
        r.reserveCapacity(a.count + b.count)
        var i = 0, j = 0
        while i < a.count || j < b.count {
            if j == b.count || (i < a.count && a[i] < b[j]) { r.append(a[i]); i += 1 }
            else if i == a.count || b[j] < a[i] { r.append(b[j]); j += 1 }
            else { r.append(a[i]); i += 1; j += 1 }
        }
        return r
    }

    func evaluatePath(_ path: ItemPath.Path, _ item: Int) -> [Int] {
        var contexts = [path.absolute ? -1 : item]
        var results: [Int] = []
        for step in path.steps {
            if contexts.count == 1 {
                results = []
                evaluateStep(step, contexts[0], &results)
            } else {
                // 여러 문맥의 결과는 표시 배열로 모아 문서 순서로 꺼낸다. O(n)
                let nested = step.slice == nil && (step.axis == .descendant || step.axis == .descendantOrSelf)
                var seen = Array(repeating: false, count: count)
                var coveredUntil = -1
                var scratch: [Int] = []
                for context in contexts {
                    if nested, context < coveredUntil { continue }
                    scratch.removeAll(keepingCapacity: true)
                    evaluateStep(step, context, &scratch)
                    for r in scratch { seen[r] = true }
                    if nested, context >= 0 { coveredUntil = index.lines[context].branchEnd }
                }
                results = seen.indices.filter { seen[$0] }
            }
            contexts = results
        }
        return results
    }

    func evaluateStep(_ step: ItemPath.Step, _ item: Int, _ results: inout [Int]) {
        let from = results.count
        func test(_ i: Int) -> Bool { matches(step.type, step.predicate, i) }
        let lines = index.lines
        switch step.axis {
        case .ancestorOrSelf, .ancestor:
            var each = step.axis == .ancestor ? (item >= 0 ? lines[item].parent : -1) : item
            while each >= 0 {
                if test(each) { results.insert(each, at: from) }
                each = lines[each].parent
            }
        case .child:
            var k = item + 1
            let end = index.branchEnd(item)
            while k < end {
                if test(k) { results.append(k) }
                k = lines[k].branchEnd
            }
        case .descendantOrSelf, .descendant:
            let start = step.axis == .descendant || item < 0 ? item + 1 : item
            for k in Swift.max(start, 0)..<index.branchEnd(item) where test(k) { results.append(k) }
        case .followingSibling:
            guard item >= 0 else { break }
            var k: Int? = index.nextSibling(item)
            while let s = k {
                if test(s) { results.append(s) }
                k = index.nextSibling(s)
            }
        case .following:
            guard item >= 0 else { break }
            for k in (item + 1)..<count where test(k) { results.append(k) }
        case .parent:
            if item >= 0, lines[item].parent >= 0, test(lines[item].parent) { results.append(lines[item].parent) }
        case .precedingSibling:
            guard item >= 0 else { break }
            var k = lines[item].previousSibling
            while k >= 0 {
                if test(k) { results.insert(k, at: from) }
                k = lines[k].previousSibling
            }
        case .preceding:
            guard item > 0 else { break }
            for k in 0..<item where test(k) { results.append(k) }
        case .selfAxis:
            if item >= 0, test(item) { results.append(item) }
        }
        applySlice(step.slice, &results, from: from)
    }

    func applySlice(_ slice: ItemPath.Slice?, _ results: inout [Int], from: Int) {
        guard let slice else { return }
        let length = results.count - from
        guard length > 0 else { return }
        var start = slice.start
        var end = slice.end.map { Swift.min($0, length) }
        guard start != 0 || end != length else { return }
        if start < 0 { start = Swift.max(start + length, 0) }
        if start > length - 1 { start = length - 1 }
        let sliced: [Int]
        if let e = end {
            var e2 = e < 0 ? e + length : e
            if e2 < start { e2 = start }
            end = e2
            sliced = Array(results[(from + start)..<(from + e2)])
        } else {
            sliced = [results[from + start]]
        }
        results.replaceSubrange(from..., with: sliced)
    }

    func matches(_ type: ItemType?, _ predicate: ItemPath.Predicate, _ i: Int) -> Bool {
        if let type, index.lines[i].type != type { return false }
        switch predicate {
        case .any: return true
        case let .and(a, b): return matches(nil, a, i) && matches(nil, b, i)
        case let .or(a, b): return matches(nil, a, i) || matches(nil, b, i)
        case let .not(a): return !matches(nil, a, i)
        case let .compare(c): return compare(c, i)
        }
    }

    // MARK: 값

    func attribute(_ name: String, _ i: Int) -> String? {
        let line = index.lines[i]
        switch name {
        case "id": return String(line.id)
        case "text": return index.body(i, text)
        case "type": return line.type.rawValue
        default:
            guard let tag = line.tag(name) else { return nil }
            return tag.value ?? ""
        }
    }

    func raw(_ value: ItemPath.Value, _ i: Int) -> String? {
        switch value {
        case let .string(s): s
        case let .attribute(name): attribute(name, i)
        case let .count(e): String(evaluate(e, i).count)
        }
    }

    /// 문자열 상수는 비교마다 한 번만 변환한다.
    func value(_ value: ItemPath.Value, _ c: ItemPath.Comparison, cache: inout [ObjectIdentifier: Val?], _ i: Int) -> Val? {
        guard case .string = value else { return raw(value, i).map { convert($0, c.modifier) } }
        if let cached = cache[ObjectIdentifier(c)] { return cached }
        let result = raw(value, i).map { convert($0, c.modifier) }
        cache[ObjectIdentifier(c)] = result
        return result
    }

    func convert(_ s: String, _ m: ItemPath.Modifier) -> Val {
        if s.isEmpty { return .str(s) }
        if m.list {
            let parts = s.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            return .list(parts.map { convertOne($0, m.element) })
        }
        return convertOne(s, m.element) ?? .str("")
    }

    func convertOne(_ s: String, _ element: Character) -> Val? {
        switch element {
        case "i": .str(s.lowercased())
        case "n": .num(parseFloat(s))
        case "d": DateParser.parse(s, now: now).map { .num($0.timeIntervalSince1970 * 1000) }
        case "b": .bool(s == "true")
        default: .str(s)
        }
    }

    func compare(_ c: ItemPath.Comparison, _ i: Int) -> Bool {
        if let fast = fastTextCompare(c, i) { return fast }
        let left = value(c.left, c, cache: &leftConstants, i)
        guard let rightValue = c.right, let relation = c.relation else { return left != nil }
        let right = value(rightValue, c, cache: &rightConstants, i)
        return relate(left, relation, right, c)
    }

    /// `@text`을 대소문자 무시로 비교할 때 본문 문자열을 만들지 않고 문서 텍스트에서 바로 찾는다.
    func fastTextCompare(_ c: ItemPath.Comparison, _ i: Int) -> Bool? {
        guard case .attribute("text") = c.left, case .string = c.right, c.modifier.element == "i", !c.modifier.list,
              let relation = c.relation, [.contains, .beginswith, .endswith].contains(relation),
              case let .str(needle)? = value(c.right!, c, cache: &rightConstants, i) else { return nil }
        let line = index.lines[i]
        let body = NSRange(location: line.bodyStart, length: line.length - line.indentLength)
        if needle.isEmpty { return relation == .contains || body.length == 0 }
        var options: NSString.CompareOptions = [.caseInsensitive]
        if relation == .beginswith { options.insert(.anchored) }
        if relation == .endswith { options.formUnion([.anchored, .backwards]) }
        return text.range(of: needle, options: options, range: body).location != NSNotFound
    }

    func relate(_ left: Val?, _ relation: ItemPath.Relation, _ right: Val?, _ c: ItemPath.Comparison) -> Bool {
        if case let .list(l)? = left, case let .list(r)? = right {
            switch relation {
            case .eq: return l.count == r.count && zip(l, r).allSatisfy { strictEqual($0, $1) }
            case .ne: return !(l.count == r.count && zip(l, r).allSatisfy { strictEqual($0, $1) })
            case .lt, .gt, .le, .ge:
                guard !l.isEmpty, !r.isEmpty else { return false }
                return r.allSatisfy { rv in l.contains { jsCompare($0, rv, relation) } }
            case .beginswith:
                guard !l.isEmpty, !r.isEmpty else { return false }
                return r.indices.allSatisfy { $0 < l.count && strictEqual(l[$0], r[$0]) }
            case .contains:
                guard !l.isEmpty, !r.isEmpty else { return false }
                return r.allSatisfy { rv in l.contains { strictEqual($0, rv) } }
            case .endswith:
                guard !l.isEmpty, !r.isEmpty, r.count <= l.count else { return false }
                return r.indices.allSatisfy { strictEqual(l[l.count - r.count + $0], r[$0]) }
            case .matches:
                let rx = regexes(for: c, right!)
                guard !rx.isEmpty, !l.isEmpty else { return false }
                return rx.allSatisfy { re in l.contains { re.firstMatch(in: $0?.text ?? "", range: NSRange(location: 0, length: ($0?.text ?? "").utf16.count)) != nil } }
            }
        }
        switch relation {
        case .eq: return strictEqual(left, right)
        case .ne: return !strictEqual(left, right)
        case .lt, .gt, .le, .ge: return jsCompare(left, right, relation)
        case .beginswith:
            guard case let .str(l)? = left, case let .str(r)? = right else { return false }
            return l.hasPrefix(r)
        case .contains:
            guard case let .str(l)? = left, case let .str(r)? = right else { return false }
            return r.isEmpty || l.contains(r)
        case .endswith:
            guard case let .str(l)? = left, case let .str(r)? = right else { return false }
            return l.hasSuffix(r)
        case .matches:
            guard let left, let right, let re = regexes(for: c, right).first else { return false }
            let t = left.text
            return re.firstMatch(in: t, range: NSRange(location: 0, length: t.utf16.count)) != nil
        }
    }

    func regexes(for c: ItemPath.Comparison, _ right: Val) -> [NSRegularExpression] {
        let key = ObjectIdentifier(c)
        if let cached = regexes[key] { return cached }
        let sources: [String] = if case let .list(items) = right { items.map { $0?.text ?? "" } } else { [right.text] }
        var result: [NSRegularExpression] = []
        for s in sources {
            guard let re = try? NSRegularExpression(pattern: s) else { result = []; break }
            result.append(re)
        }
        regexes[key] = result
        return result
    }
}

