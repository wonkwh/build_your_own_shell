import Foundation

/// 줄 종류. TaskPaper 규칙과 같다.
enum ItemType: String, Sendable {
    case project, task, note
}

/// `@name(value)` 태그. 범위는 줄 시작 기준이다.
struct Tag: Equatable, Sendable {
    var name: String
    var value: String?
    /// `@`부터 태그 끝까지
    var range: NSRange
    /// 앞 공백까지 포함
    var fullRange: NSRange
}

/// 텍스트 한 줄과 그 줄이 나타내는 항목.
struct Line: Sendable {
    var id: Int
    var start: Int
    /// 줄 끝 문자를 뺀 길이
    var length: Int
    /// 0, 1(\n), 2(\r\n)
    var terminator: Int
    var indentLength: Int
    var level: Int
    var type: ItemType
    var tags: [Tag]
    /// 끝 태그를 뺀 본문 끝, 줄 시작 기준
    var contentEnd: Int
    var depth = 0
    var parent = -1
    var branchEnd = 0
    var previousSibling = -1
    var collapsed = false
    /// 내용 해시. 다시 파싱할 때 같은 줄을 찾아 id·접힘을 넘긴다
    var hash = 0

    var end: Int { start + length }
    var fullEnd: Int { start + length + terminator }
    var bodyStart: Int { start + indentLength }
    var isBlank: Bool { indentLength == length }
    var range: NSRange { NSRange(location: start, length: length) }
    var fullRange: NSRange { NSRange(location: start, length: length + terminator) }

    func tag(_ name: String) -> Tag? { tags.first { $0.name == name } }
}

/// 문서 텍스트를 줄 단위로 파싱하고 편집된 줄만 다시 파싱한다.
final class LineIndex {
    /// 공백 들여쓰기 몇 칸을 한 단계로 볼지
    nonisolated(unsafe) static var spacesPerLevel = 4

    private(set) var lines: [Line] = []
    private var nextID = 0

    init(_ text: NSString) {
        lines = parse(text, from: 0, to: text.length, final: true)
        rebuildStructure()
    }

    var count: Int { lines.count }
    subscript(i: Int) -> Line { lines[i] }

    /// `location`을 포함하는 줄 번호. 줄 끝 문자는 그 줄에 속한다.
    func line(at location: Int) -> Int {
        var lo = 0, hi = lines.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lines[mid].start <= location { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    /// 편집 뒤 바뀐 줄만 다시 파싱한다.
    /// - Parameters:
    ///   - editedRange: 새 텍스트 기준 편집 범위
    ///   - delta: 길이 변화량
    func update(_ text: NSString, editedRange: NSRange, delta: Int) {
        let oldLocation = editedRange.location
        let oldEnd = editedRange.location + editedRange.length - delta
        let first = line(at: oldLocation)
        let last = line(at: oldEnd)
        let isFinal = last == lines.count - 1
        let regionStart = lines[first].start
        let regionEnd = isFinal ? text.length : lines[last + 1].start + delta
        var fresh = parse(text, from: regionStart, to: regionEnd, final: isFinal)

        // 같은 내용의 옛 줄과 먼저 짝짓고, 남은 줄은 순서대로 짝지어 id·접힘을 넘긴다
        let old = Array(lines[first...last])
        var byHash: [Int: [Int]] = [:]
        for (k, o) in old.enumerated().reversed() { byHash[o.hash, default: []].append(k) }
        var used = Array(repeating: false, count: old.count)
        var unmatched: [Int] = []
        for n in fresh.indices {
            if let k = byHash[fresh[n].hash]?.popLast() {
                used[k] = true
                fresh[n].id = old[k].id
                fresh[n].collapsed = old[k].collapsed
            } else {
                unmatched.append(n)
            }
        }
        var leftovers = old.indices.filter { !used[$0] }.makeIterator()
        for n in unmatched {
            guard let k = leftovers.next() else { break }
            fresh[n].id = old[k].id
            fresh[n].collapsed = old[k].collapsed
        }
        lines.replaceSubrange(first...last, with: fresh)
        if delta != 0 {
            for k in (first + fresh.count)..<lines.count { lines[k].start += delta }
        }
        rebuildStructure()
    }

    /// 줄 범위의 접힘 상태와 id를 다른 줄에서 가져온다. 명령이 줄을 옮긴 뒤 쓴다.
    func carry(startingAt first: Int, from sources: [Line?]) {
        let carried = Set(sources.compactMap { $0?.id }.filter { $0 >= 0 })
        for (k, source) in sources.enumerated() where first + k < lines.count {
            if let source, source.id >= 0 {
                lines[first + k].id = source.id
            } else if carried.contains(lines[first + k].id) {
                // 이어받은 id와 겹치면 새 id를 준다
                nextID += 1
                lines[first + k].id = nextID
            }
            if let source { lines[first + k].collapsed = source.collapsed }
        }
    }

    func setCollapsed(_ i: Int, _ value: Bool) { lines[i].collapsed = value }

    // MARK: - 파싱

    private func parse(_ text: NSString, from: Int, to: Int, final: Bool) -> [Line] {
        var result: [Line] = []
        var pos = from
        while pos < to {
            let newline = text.range(of: "\n", options: .literal, range: NSRange(location: pos, length: to - pos))
            if newline.location == NSNotFound { break }
            var end = newline.location
            var terminator = 1
            if end > pos, text.character(at: end - 1) == 13 { end -= 1; terminator = 2 }
            result.append(parseLine(text, start: pos, length: end - pos, terminator: terminator))
            pos = newline.location + 1
        }
        if final { result.append(parseLine(text, start: pos, length: to - pos, terminator: 0)) }
        return result
    }

    private func parseLine(_ text: NSString, start: Int, length: Int, terminator: Int) -> Line {
        nextID += 1
        var indent = 0, level = 0, spaces = 0
        while indent < length {
            let c = text.character(at: start + indent)
            if c == 9 { level += 1 } else if c == 32 { spaces += 1 } else { break }
            indent += 1
        }
        level += spaces / Self.spacesPerLevel

        var tags: [Tag] = []
        var contentEnd = length
        let bodyRange = NSRange(location: start + indent, length: length - indent)
        if bodyRange.length > 0, text.range(of: "@", options: .literal, range: bodyRange).location != NSNotFound {
            tags = Self.parseTags(text.substring(with: bodyRange), offset: indent)
            contentEnd = Self.trailingTagsStart(text, start: start, length: length, tags: tags)
        }
        let type = Self.parseType(text, contentStart: start + indent, contentEnd: start + contentEnd)
        var line = Line(id: nextID, start: start, length: length, terminator: terminator, indentLength: indent,
                        level: level, type: type, tags: tags, contentEnd: contentEnd)
        line.hash = text.substring(with: NSRange(location: start, length: length)).hashValue
        return line
    }

    static let tagRegex: NSRegularExpression = {
        let start = "A-Z_a-z\\u00C0-\\u00D6\\u00D8-\\u00F6\\u00F8-\\u02FF\\u0370-\\u037D\\u037F-\\u1FFF\\u200C-\\u200D\\u2070-\\u218F\\u2C00-\\u2FEF\\u3001-\\uD7FF\\uF900-\\uFDCF\\uFDF0-\\uFFFD"
        let rest = "\\-.0-9\\u00B7\\u0300-\\u036F\\u203F-\\u2040"
        let pattern = "(^|\\s+)@([\(start)\(rest)]+)(?:\\(((?:\\\\\\(|\\\\\\)|[^()])*)\\))?(?=\\s|$)"
        return try! NSRegularExpression(pattern: pattern)
    }()

    /// 본문에서 태그를 찾는다. 범위는 `offset`을 더해 줄 시작 기준으로 돌려준다.
    static func parseTags(_ body: String, offset: Int) -> [Tag] {
        let ns = body as NSString
        return tagRegex.matches(in: body, range: NSRange(location: 0, length: ns.length)).map { m in
            let lead = m.range(at: 1).length
            let valueRange = m.range(at: 3)
            let value = valueRange.location == NSNotFound ? nil : unescapeTagValue(ns.substring(with: valueRange))
            return Tag(name: ns.substring(with: m.range(at: 2)), value: value,
                       range: NSRange(location: m.range.location + lead + offset, length: m.range.length - lead),
                       fullRange: NSRange(location: m.range.location + offset, length: m.range.length))
        }
    }

    static func unescapeTagValue(_ s: String) -> String {
        s.replacingOccurrences(of: "\\)", with: ")").replacingOccurrences(of: "\\(", with: "(")
    }

    static func escapeTagValue(_ s: String) -> String {
        s.replacingOccurrences(of: ")", with: "\\)").replacingOccurrences(of: "(", with: "\\(")
    }

    /// 줄 끝까지 이어지는 태그 묶음의 시작. 없으면 `length`.
    private static func trailingTagsStart(_ text: NSString, start: Int, length: Int, tags: [Tag]) -> Int {
        var trimmedEnd = length
        while trimmedEnd > 0 {
            let c = text.character(at: start + trimmedEnd - 1)
            if c == 32 || c == 9 { trimmedEnd -= 1 } else { break }
        }
        guard let lastTag = tags.last, NSMaxRange(lastTag.range) == trimmedEnd else { return length }
        var result = lastTag.fullRange.location
        for tag in tags.dropLast().reversed() where NSMaxRange(tag.fullRange) == result {
            result = tag.fullRange.location
        }
        return result
    }

    private static func parseType(_ text: NSString, contentStart: Int, contentEnd: Int) -> ItemType {
        let length = contentEnd - contentStart
        if length >= 2, text.character(at: contentStart) == 45 {
            let c = text.character(at: contentStart + 1)
            if c == 32 || c == 9 { return .task }
        }
        if length >= 1, text.character(at: contentEnd - 1) == 58 { return .project }
        return .note
    }

    // MARK: - 구조

    /// 깊이·부모·가지 끝·이전 형제를 다시 계산한다. O(n)
    private func rebuildStructure() {
        let n = lines.count
        var nextLevel = 0, sawItem = false
        for i in stride(from: n - 1, through: 0, by: -1) {
            if lines[i].isBlank {
                // 빈 줄은 다음 항목의 깊이를 따른다. 문서 끝 빈 줄은 최상위
                lines[i].depth = sawItem ? max(lines[i].level, nextLevel) : 0
            } else {
                lines[i].depth = lines[i].level
                nextLevel = lines[i].level
                sawItem = true
            }
        }
        var stack: [Int] = []
        for i in 0..<n {
            var lastPopped = -1
            while let top = stack.last, lines[top].depth >= lines[i].depth {
                lines[top].branchEnd = i
                lastPopped = top
                stack.removeLast()
            }
            lines[i].parent = stack.last ?? -1
            lines[i].previousSibling = lastPopped
            stack.append(i)
        }
        for i in stack { lines[i].branchEnd = n }
    }
}

// MARK: - 트리 탐색

extension LineIndex {
    func hasChildren(_ i: Int) -> Bool { lines[i].branchEnd > i + 1 }

    func branchEnd(_ i: Int) -> Int { i < 0 ? lines.count : lines[i].branchEnd }

    func firstChild(_ i: Int) -> Int? {
        let c = i + 1
        return c < branchEnd(i) ? c : nil
    }

    func children(_ i: Int) -> [Int] {
        var result: [Int] = []
        var k = i + 1
        let end = branchEnd(i)
        while k < end { result.append(k); k = lines[k].branchEnd }
        return result
    }

    func nextSibling(_ i: Int) -> Int? {
        let e = lines[i].branchEnd
        return e < lines.count && lines[e].parent == lines[i].parent ? e : nil
    }

    func previousSibling(_ i: Int) -> Int? {
        let p = lines[i].previousSibling
        return p >= 0 ? p : nil
    }

    /// `a`가 `b`의 조상인지. -1은 문서 루트.
    func isAncestor(_ a: Int, of b: Int) -> Bool { b > a && b < branchEnd(a) }

    func ancestors(_ i: Int) -> [Int] {
        var result: [Int] = []
        var p = lines[i].parent
        while p >= 0 { result.append(p); p = lines[p].parent }
        return result
    }

    /// 겹치는 가지를 빼고 가장 위의 항목만 남긴다. 입력은 정렬돼 있어야 한다.
    func commonAncestors(_ items: [Int]) -> [Int] {
        var result: [Int] = []
        var end = -1
        for i in items where i >= end {
            result.append(i)
            end = lines[i].branchEnd
        }
        return result
    }

    // MARK: 텍스트

    func body(_ i: Int, _ text: NSString) -> String {
        let l = lines[i]
        return text.substring(with: NSRange(location: l.bodyStart, length: l.length - l.indentLength))
    }

    /// 종류 표시(`- `, `:`)와 끝 태그를 뺀 본문. 사이드바·팔레트 이름으로 쓴다.
    func displayName(_ i: Int, _ text: NSString) -> String {
        let l = lines[i]
        var s = l.bodyStart, e = l.start + l.contentEnd
        if l.type == .task { s += 2 }
        if l.type == .project { e -= 1 }
        guard e > s else { return "" }
        return text.substring(with: NSRange(location: s, length: e - s)).trimmingCharacters(in: .whitespaces)
    }

    func indentString(_ i: Int, _ text: NSString) -> String {
        let l = lines[i]
        return text.substring(with: NSRange(location: l.start, length: l.indentLength))
    }
}
