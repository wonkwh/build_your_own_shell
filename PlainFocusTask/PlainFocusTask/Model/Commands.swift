import Foundation

/// 명령이 바꿀 새 줄. `source`는 옛 줄 번호(접힘·id를 이어받는다).
struct NewLine {
    var text: String
    var source: Int?
    var clone = false
}

/// 텍스트 한 구간을 바꾸는 편집 계획.
struct Edit {
    var range: NSRange
    var text: String
    var selection: NSRange
    /// 바뀐 구간의 첫 줄 번호(새 문서 기준)
    var firstLine: Int
    /// 바뀐 구간의 새 줄마다 이어받을 옛 줄. id가 -1이면 새 id를 쓴다
    var carry: [Line?]
    /// 펼칠 항목 id. 옮긴 항목이 접힌 부모 아래로 숨지 않게 한다
    var expandIDs: [Int] = []
}

/// 명령 계산에 필요한 편집기 상태.
struct EditorSnapshot {
    let text: NSString
    let index: LineIndex
    let hidden: [Bool]
    let selection: NSRange
    /// 포커스·호이스트 때문에 이보다 얕게 내어쓰지 않는다
    var minLevel = 0

    init(text: NSString, index: LineIndex, hidden: [Bool]? = nil, selection: NSRange, minLevel: Int = 0) {
        self.text = text
        self.index = index
        self.hidden = hidden ?? Array(repeating: false, count: index.count)
        self.selection = selection
        self.minLevel = minLevel
    }

    var n: Int { index.count }

    func lineText(_ i: Int) -> String { text.substring(with: index[i].range) }

    func allLines() -> [NewLine] { (0..<n).map { NewLine(text: lineText($0), source: $0) } }

    // MARK: 선택

    /// 선택이 걸친 줄. 다음 줄 시작에서 끝나는 선택은 그 줄을 빼다.
    var selectedLines: ClosedRange<Int> {
        let a = index.line(at: selection.location)
        var b = index.line(at: NSMaxRange(selection))
        if selection.length > 0, b > a, index[b].start == NSMaxRange(selection) { b -= 1 }
        return a...b
    }

    var visibleSelected: [Int] { selectedLines.filter { !hidden[$0] } }

    var cursorLine: Int { index.line(at: selection.location) }

    /// 선택 줄 뒤에 이어지는 숨은 자손까지 넓힌다.
    func withTrailingHidden(_ range: ClosedRange<Int>) -> ClosedRange<Int> {
        var end = range.upperBound
        let branchEnd = range.map { index[$0].branchEnd }.max() ?? end + 1
        while end + 1 < n, end + 1 < branchEnd, hidden[end + 1] { end += 1 }
        return range.lowerBound...end
    }

    func previousVisible(_ i: Int) -> Int? {
        var k = i - 1
        while k >= 0 { if !hidden[k] { return k }; k -= 1 }
        return nil
    }

    func nextVisible(_ i: Int) -> Int? {
        var k = i + 1
        while k < n { if !hidden[k] { return k }; k += 1 }
        return nil
    }

    func column(_ location: Int) -> Int { location - index[index.line(at: location)].start }

    // MARK: 편집 만들기

    /// 문서 전체의 새 줄 목록을 옛 줄과 비교해 바뀐 구간만 편집으로 만든다.
    /// - Parameters:
    ///   - select: 새 줄 번호와 열. `to`가 있으면 범위 선택
    func makeEdit(_ new: [NewLine], select: (line: Int, column: Int), to: (line: Int, column: Int)? = nil) -> Edit? {
        var p = 0
        while p < n, p < new.count, new[p].source == p, !new[p].clone, new[p].text == lineText(p) { p += 1 }
        var s = 0
        while s < n - p, s < new.count - p, new[new.count - 1 - s].source == n - 1 - s, !new[new.count - 1 - s].clone,
              new[new.count - 1 - s].text == lineText(n - 1 - s) { s += 1 }
        let oldCount = n - p - s
        let region = Array(new[p..<(new.count - s)])
        guard oldCount > 0 || !region.isEmpty else { return nil }
        let joined = region.map(\.text).joined(separator: "\n")
        let range: NSRange
        let replacement: String
        var regionStart: Int
        if oldCount > 0, !region.isEmpty {
            range = NSRange(location: index[p].start, length: index[p + oldCount - 1].end - index[p].start)
            replacement = joined
            regionStart = range.location
        } else if oldCount > 0 {
            let q = p + oldCount - 1
            if q + 1 < n {
                range = NSRange(location: index[p].start, length: index[q + 1].start - index[p].start)
            } else if p > 0 {
                range = NSRange(location: index[p - 1].end, length: index[q].end - index[p - 1].end)
            } else {
                range = NSRange(location: 0, length: text.length)
            }
            replacement = ""
            regionStart = range.location
        } else if p < n {
            range = NSRange(location: index[p].start, length: 0)
            replacement = joined + "\n"
            regionStart = range.location
        } else {
            range = NSRange(location: text.length, length: 0)
            replacement = "\n" + joined
            regionStart = range.location + 1
        }
        let delta = (replacement as NSString).length - range.length

        func start(ofNew k: Int) -> Int {
            if k < p { return index[k].start }
            if k < new.count - s {
                var pos = regionStart
                for j in p..<k { pos += (new[j].text as NSString).length + 1 }
                return pos
            }
            return index[n - (new.count - k)].start + delta
        }
        func location(_ spec: (line: Int, column: Int)) -> Int {
            let k = min(max(spec.line, 0), new.count - 1)
            let length = (new[k].text as NSString).length
            return start(ofNew: k) + min(max(spec.column, 0), length)
        }
        let a = location(select)
        let b = to.map(location) ?? a
        let carry: [Line?] = region.map { nl in
            guard let src = nl.source else { return nil }
            var line = index[src]
            if nl.clone { line.id = -1 }
            return line
        }
        return Edit(range: range, text: replacement, selection: NSRange(location: min(a, b), length: abs(b - a)), firstLine: p, carry: carry)
    }

    /// 선택 위치를 줄 번호·열로 바꾼다. 다른 줄 목록으로 옮긴 뒤 선택을 다시 계산할 때 쓴다.
    var selectionSpec: (start: (line: Int, column: Int), end: (line: Int, column: Int)) {
        let a = index.line(at: selection.location), b = index.line(at: NSMaxRange(selection))
        return ((a, selection.location - index[a].start), (b, NSMaxRange(selection) - index[b].start))
    }

    /// 옛 줄 번호를 새 목록에서 찾아 선택을 옮긴다.
    func editKeepingSelection(_ new: [NewLine], columnShift: (Int) -> Int = { _ in 0 }) -> Edit? {
        let spec = selectionSpec
        func map(_ s: (line: Int, column: Int)) -> (line: Int, column: Int) {
            if let k = new.firstIndex(where: { $0.source == s.line && !$0.clone }) { return (k, s.column + columnShift(s.line)) }
            return (min(s.line, new.count - 1), 0)
        }
        return makeEdit(new, select: map(spec.start), to: selection.length > 0 ? map(spec.end) : nil)
    }
}

// MARK: - 들여쓰기·태그 문자열 도구

enum LineText {
    static func indentLength(_ s: String) -> Int {
        var k = 0
        for c in s.utf16 { if c == 9 || c == 32 { k += 1 } else { break } }
        return k
    }

    static func level(_ s: String) -> Int {
        var level = 0, spaces = 0
        for c in s.utf16 {
            if c == 9 { level += 1 } else if c == 32 { spaces += 1 } else { break }
        }
        return level + spaces / LineIndex.spacesPerLevel
    }

    /// 들여쓰기를 `delta` 단계만큼 바꾼다. 음수면 앞쪽 탭이나 공백을 지운다.
    static func reindent(_ s: String, by delta: Int) -> String {
        if delta > 0 { return String(repeating: "\t", count: delta) + s }
        var u = Substring(s)
        for _ in 0..<(-delta) {
            if u.hasPrefix("\t") { u = u.dropFirst() }
            else if u.hasPrefix(" ") {
                var k = 0
                while k < LineIndex.spacesPerLevel, u.hasPrefix(" ") { u = u.dropFirst(); k += 1 }
            } else { break }
        }
        return String(u)
    }

    static func tags(_ s: String) -> [Tag] {
        let indent = indentLength(s)
        let ns = s as NSString
        return LineIndex.parseTags(ns.substring(from: indent), offset: indent)
    }

    static func encodeTag(_ name: String, _ value: String?) -> String {
        guard let value, !value.isEmpty else { return "@" + name }
        return "@\(name)(\(LineIndex.escapeTagValue(value)))"
    }

    static func removeTag(_ s: String, _ name: String) -> String {
        guard let tag = tags(s).first(where: { $0.name == name }) else { return s }
        var range = tag.fullRange
        let ns = s as NSString
        // 본문 맨 앞 태그면 뒤 공백 하나도 지운다
        if tag.fullRange.location == indentLength(s), NSMaxRange(range) < ns.length, ns.character(at: NSMaxRange(range)) == 32 {
            range.length += 1
        }
        return ns.replacingCharacters(in: range, with: "")
    }

    static func setTag(_ s: String, _ name: String, _ value: String?) -> String {
        let ns = s as NSString
        let encoded = encodeTag(name, value)
        if let tag = tags(s).first(where: { $0.name == name }) {
            let lead = tag.fullRange.location > indentLength(s) ? " " : ""
            return ns.replacingCharacters(in: tag.fullRange, with: lead + encoded)
        }
        let body = ns.substring(from: indentLength(s))
        if body.isEmpty { return s + encoded }
        if body.last?.isWhitespace == true { return s + encoded }
        return s + " " + encoded
    }

    static func removeAllTags(_ s: String, keeping keep: Set<String> = []) -> String {
        var result = s
        for tag in tags(s).reversed() where !keep.contains(tag.name) {
            result = (result as NSString).replacingCharacters(in: tag.fullRange, with: "")
        }
        return result
    }

    /// 프로젝트·작업·메모 표시를 바꾼다.
    static func format(_ s: String, as type: ItemType) -> String {
        let indent = indentLength(s)
        let ns = s as NSString
        var body = ns.substring(from: indent)
        let parsed = LineIndex(ns)
        let line = parsed[0]
        let contentEnd = line.contentEnd - indent
        var content = (body as NSString).substring(to: contentEnd)
        let trailing = (body as NSString).substring(from: contentEnd)
        switch line.type {
        case .task: content = String(content.dropFirst(2))
        case .project: content = String(content.dropLast())
        case .note: break
        }
        switch type {
        case .task: content = "- " + content
        case .project: content += ":"
        case .note: break
        }
        body = content + trailing
        return ns.substring(to: indent) + body
    }
}

// MARK: - 명령

extension EditorSnapshot {
    /// 줄(과 숨은 자손) 들여쓰기·내어쓰기. Tab, Shift-Tab, Move Right/Left.
    func shiftLines(_ delta: Int) -> Edit? {
        let range = withTrailingHidden(selectedLines)
        var new = allLines()
        var shifts: [Int: Int] = [:]
        for i in range {
            let old = new[i].text
            if delta < 0, LineText.level(old) <= minLevel { continue }
            new[i].text = LineText.reindent(old, by: delta)
            shifts[i] = (new[i].text as NSString).length - (old as NSString).length
        }
        return editKeepingSelection(new) { shifts[$0] ?? 0 }
    }

    /// 가지 단위 오른쪽(앞 형제의 마지막 자식으로)·왼쪽(부모 가지 뒤로) 이동.
    func shiftBranches(_ delta: Int) -> Edit? {
        let tops = index.commonAncestors(visibleSelected)
        guard let first = tops.first, let last = tops.last else { return nil }
        let end = index[last].branchEnd
        var new = allLines()
        if delta > 0 {
            guard let sibling = index.previousSibling(first), !hidden[sibling] else { return nil }
            let d = index[sibling].level + 1 - index[first].level
            for i in first..<end { new[i].text = LineText.reindent(new[i].text, by: d) }
            var edit = editKeepingSelection(new) { i in (i >= first && i < end) ? d : 0 }
            edit?.expandIDs = [index[sibling].id]
            return edit
        }
        let parent = index[first].parent
        guard parent >= 0, index[parent].level >= minLevel else { return nil }
        let d = index[parent].level - index[first].level
        let block = (first..<end).map { NewLine(text: LineText.reindent(lineText($0), by: d), source: $0) }
        let insertAt = index[parent].branchEnd
        let result = Array(new[0..<first]) + Array(new[end..<insertAt]) + block + Array(new[insertAt...])
        let spec = selectionSpec
        let k = result.firstIndex { $0.source == spec.start.line } ?? 0
        return makeEdit(result, select: (k, spec.start.column + d))
    }

    /// 줄(과 숨은 자손)을 위·아래 보이는 줄 너머로 옮긴다. 들여쓰기는 그대로.
    func moveLines(up: Bool) -> Edit? {
        let range = withTrailingHidden(selectedLines)
        let minDepth = range.map { index[$0].depth }.min() ?? 0
        func firstAfter(_ x: Int) -> Int {
            var k = x + 1
            while k < n, hidden[k], index[k].depth > minDepth { k += 1 }
            return k
        }
        let target: Int
        if up {
            guard let p = previousVisible(range.lowerBound) else { return nil }
            target = previousVisible(p).map(firstAfter) ?? p
        } else {
            guard let after = nextVisible(range.upperBound) else { return nil }
            target = firstAfter(after)
        }
        return moveBlock(range, before: target, levelDelta: 0)
    }

    /// 가지를 위·아래로 옮긴다. 옮긴 뒤 새 부모에 맞게 들여쓰기를 바꾼다.
    func moveBranches(up: Bool) -> Edit? {
        let tops = index.commonAncestors(visibleSelected)
        guard let first = tops.first, let last = tops.last else { return nil }
        let block = first...(index[last].branchEnd - 1)
        if up {
            guard let p = previousVisible(first) else { return nil }
            return moveBlock(block, before: p, levelDelta: index[p].level - index[first].level)
        }
        guard let n1 = nextVisible(block.upperBound) else { return nil }
        if let n2 = nextVisible(n1) {
            return moveBlock(block, before: n2, levelDelta: index[n2].level - index[first].level)
        }
        return moveBlock(block, before: n, levelDelta: index[n1].level - index[first].level)
    }

    /// 손잡이 끌어놓기: 가지를 `target` 앞으로 옮기고 단계를 `level`로 맞춘다.
    func moveBranch(_ i: Int, before target: Int, level: Int) -> Edit? {
        let block = i...(index[i].branchEnd - 1)
        let delta = level - index[i].level
        if target == block.lowerBound || target == block.upperBound + 1 {
            guard delta != 0 else { return nil }
            var new = allLines()
            for k in block { new[k].text = LineText.reindent(new[k].text, by: delta) }
            return makeEdit(new, select: (i, LineText.indentLength(new[i].text)))
        }
        guard target < block.lowerBound || target > block.upperBound + 1 else { return nil }
        let newIndex = target < i ? target : target - block.count
        let moved = movedLines(block, before: target, delta: delta)
        return makeEdit(moved, select: (newIndex, LineText.indentLength(moved[newIndex].text)))
    }

    private func movedLines(_ block: ClosedRange<Int>, before target: Int, delta: Int) -> [NewLine] {
        let all = allLines()
        let moved = block.map { NewLine(text: LineText.reindent(lineText($0), by: delta), source: $0) }
        if target < block.lowerBound {
            return Array(all[0..<target]) + moved + Array(all[target..<block.lowerBound]) + Array(all[(block.upperBound + 1)...])
        }
        return Array(all[0..<block.lowerBound]) + Array(all[(block.upperBound + 1)..<target]) + moved + Array(all[target...])
    }

    func moveBlock(_ block: ClosedRange<Int>, before target: Int, levelDelta: Int) -> Edit? {
        guard target < block.lowerBound || target > block.upperBound + 1 else { return nil }
        let result = movedLines(block, before: target, delta: levelDelta)
        let first = lineText(block.lowerBound)
        let shift = (LineText.reindent(first, by: levelDelta) as NSString).length - (first as NSString).length
        return editKeepingSelection(result) { block.contains($0) ? shift : 0 }
    }

    /// 선택 줄을 새 빈 항목 아래로 묶는다.
    func groupLines() -> Edit? {
        let range = withTrailingHidden(selectedLines)
        let first = range.lowerBound
        let minLevel = range.filter { !index[$0].isBlank }.map { index[$0].level }.min() ?? index[first].level
        let delta = index[first].level + 1 - minLevel
        var result = Array(allLines()[0..<first])
        result.append(NewLine(text: index.indentString(first, text), source: nil))
        result += range.map { NewLine(text: LineText.reindent(lineText($0), by: delta), source: $0) }
        result += allLines()[(range.upperBound + 1)...]
        return makeEdit(result, select: (first, index[first].indentLength))
    }

    func duplicateLines() -> Edit? {
        let range = withTrailingHidden(selectedLines)
        var result = allLines()
        let clones = range.map { NewLine(text: lineText($0), source: $0, clone: true) }
        result.insert(contentsOf: clones, at: range.upperBound + 1)
        let spec = selectionSpec
        let offset = range.count
        return makeEdit(result, select: (spec.start.line + offset, spec.start.column),
                        to: selection.length > 0 ? (spec.end.line + offset, spec.end.column) : nil)
    }

    func deleteLines() -> Edit? {
        let range = withTrailingHidden(selectedLines)
        var result = allLines()
        result.removeSubrange(range)
        if result.isEmpty { result = [NewLine(text: "", source: nil)] }
        let k = min(range.lowerBound, result.count - 1)
        return makeEdit(result, select: (k, LineText.indentLength(result[k].text)))
    }

    func format(as type: ItemType) -> Edit? {
        var new = allLines()
        var shifts: [Int: Int] = [:]
        for i in visibleSelected where !index[i].isBlank {
            let old = new[i].text
            new[i].text = LineText.format(old, as: type)
            shifts[i] = type == .task && index[i].type != .task ? 2 : (index[i].type == .task && type != .task ? -2 : 0)
        }
        return editKeepingSelection(new) { shifts[$0] ?? 0 }
    }

    /// 선택한 모든 항목에 태그가 있으면 지우고, 아니면 붙인다.
    func toggleTag(_ name: String, value: String? = nil) -> Edit? {
        let lines = visibleSelected.filter { !index[$0].isBlank }
        guard !lines.isEmpty else { return nil }
        let all = lines.allSatisfy { index[$0].tag(name) != nil }
        return setTag(name, value: value, remove: all, on: lines)
    }

    func setTag(_ name: String, value: String?, remove: Bool, on lines: [Int]? = nil) -> Edit? {
        var new = allLines()
        for i in lines ?? visibleSelected.filter({ !index[$0].isBlank }) {
            new[i].text = remove ? LineText.removeTag(new[i].text, name) : LineText.setTag(new[i].text, name, value)
        }
        return editKeepingSelection(new)
    }

    func hasTag(_ name: String) -> Bool {
        let lines = visibleSelected.filter { !index[$0].isBlank }
        return !lines.isEmpty && lines.allSatisfy { index[$0].tag(name) != nil }
    }

    func clearTags() -> Edit? {
        var new = allLines()
        for i in visibleSelected { new[i].text = LineText.removeAllTags(new[i].text) }
        return editKeepingSelection(new)
    }

    /// @done 항목을 `Archive:` 프로젝트 맨 앞으로 옮긴다.
    func archiveDone(addProjectTag: Bool = true, removeExtraTags: Bool = false) -> Edit? {
        let archive = (0..<n).first { index.body($0, text).lowercased() == "archive:" }
        let done = (0..<n).filter { i in
            index[i].tag("done") != nil && !(archive.map { index.isAncestor($0, of: i) } ?? false)
        }
        let tops = index.commonAncestors(done)
        guard !tops.isEmpty else { return nil }
        var removed = Set<Int>()
        var moved: [NewLine] = []
        let archiveLevel = archive.map { index[$0].level } ?? 0
        for t in tops {
            let delta = archiveLevel + 1 - index[t].level
            for k in t..<index[t].branchEnd {
                removed.insert(k)
                var s = LineText.reindent(lineText(k), by: delta)
                if k == t {
                    if removeExtraTags { s = LineText.removeAllTags(s, keeping: ["done"]) }
                    let projects = index.ancestors(t).reversed().filter { index[$0].type == .project }.map { index.displayName($0, text) }
                    if addProjectTag, !projects.isEmpty { s = LineText.setTag(s, "project", projects.joined(separator: " / ")) }
                }
                moved.append(NewLine(text: s, source: k))
            }
        }
        var result = (0..<n).filter { !removed.contains($0) }.map { NewLine(text: lineText($0), source: $0) }
        if let archive, let pos = result.firstIndex(where: { $0.source == archive }) {
            result.insert(contentsOf: moved, at: pos + 1)
        } else {
            var end = result.count
            while end > 0, result[end - 1].text.isEmpty { end -= 1 }
            result.insert(contentsOf: [NewLine(text: "Archive:", source: nil)] + moved, at: end)
        }
        let c = cursorLine
        if let k = result.firstIndex(where: { $0.source == c }), !removed.contains(c) {
            return makeEdit(result, select: (k, selection.location - index[c].start))
        }
        var prev = c - 1
        while prev >= 0, removed.contains(prev) { prev -= 1 }
        let k = prev >= 0 ? (result.firstIndex { $0.source == prev } ?? 0) : 0
        return makeEdit(result, select: (k, prev >= 0 ? (result[k].text as NSString).length : 0))
    }

    /// 선택 가지를 프로젝트(nil이면 문서 맨 앞)의 첫 자식으로 옮긴다. `newProject`가 있으면 맨 앞에 만든다.
    func moveToProject(_ target: Int?, newProject: String? = nil) -> Edit? {
        let tops = index.commonAncestors(visibleSelected)
        guard let firstTop = tops.first else { return nil }
        if let target, tops.contains(where: { $0 == target || index.isAncestor($0, of: target) }) { return nil }
        let targetLevel = newProject != nil ? 0 : (target.map { index[$0].level } ?? -1)
        var removed = Set<Int>()
        var moved: [NewLine] = []
        for t in tops {
            let delta = targetLevel + 1 - index[t].level
            for k in t..<index[t].branchEnd {
                removed.insert(k)
                moved.append(NewLine(text: LineText.reindent(lineText(k), by: delta), source: k))
            }
        }
        var result = (0..<n).filter { !removed.contains($0) }.map { NewLine(text: lineText($0), source: $0) }
        var insertAt = 0
        if let newProject {
            result.insert(NewLine(text: newProject + ":", source: nil), at: 0)
            insertAt = 1
        } else if let target, let pos = result.firstIndex(where: { $0.source == target }) {
            insertAt = pos + 1
        }
        result.insert(contentsOf: moved, at: insertAt)
        var edit = makeEdit(result, select: (insertAt, LineText.indentLength(moved[0].text) + (index[firstTop].type == .task ? 2 : 0)))
        if let target { edit?.expandIDs = [index[target].id] }
        return edit
    }

    /// 새 항목이 들어갈 줄 번호와 들여쓰기. 보이는 자식이 있으면 첫 자식 자리, 아니면 가지 뒤.
    func insertionPoint(after i: Int) -> (line: Int, indent: String) {
        if let next = nextVisible(i), index.isAncestor(i, of: next) {
            return (next, index.indentString(next, text))
        }
        return (index[i].branchEnd, index.indentString(i, text))
    }

    /// New Task·Note·Project: 현재 항목 아래에 넣고 이름 부분을 선택한다.
    func insertItem(_ body: String, selectFrom: Int, selectTo: Int) -> Edit? {
        let (at, indent) = insertionPoint(after: cursorLine)
        var result = allLines()
        result.insert(NewLine(text: indent + body, source: nil), at: at)
        let base = (indent as NSString).length
        return makeEdit(result, select: (at, base + selectFrom), to: (at, base + selectTo))
    }

    /// Return. 작업 줄은 `- `를 이어 붙이고, 빈 작업 줄은 대시를 지운다. nil이면 기본 동작.
    func insertNewline() -> Edit? {
        guard selection.length == 0 else { return nil }
        let i = cursorLine
        let line = index[i]
        let body = index.body(i, text)
        let col = max(0, selection.location - line.bodyStart)
        let prefix = body.hasPrefix("- ") ? "- " : ""
        let content = String(body.dropFirst(prefix.count))
        let lead = prefix.utf16.count
        var result = allLines()
        let indent = index.indentString(i, text)
        if col <= lead, !body.isEmpty, prefix.isEmpty || !content.isEmpty {
            result.insert(NewLine(text: indent, source: nil), at: i)
            return makeEdit(result, select: (i + 1, line.indentLength + col))
        }
        if col == lead, !prefix.isEmpty, content.isEmpty {
            result[i].text = indent
            return makeEdit(result, select: (i, line.indentLength))
        }
        let ns = body as NSString
        let head = ns.substring(to: col)
        var tail = ns.substring(from: col)
        if !prefix.isEmpty, !tail.hasPrefix(prefix) { tail = prefix + tail }
        result[i].text = indent + head
        let (at, newIndent) = insertionPoint(after: i)
        result.insert(NewLine(text: newIndent + tail, source: nil), at: at)
        return makeEdit(result, select: (at, (newIndent as NSString).length + (prefix.isEmpty ? 0 : lead)))
    }

    /// 본문 맨 앞에서 Backspace: 들여쓴 줄은 내어쓰고, 앞줄이 숨어 있으면 앞의 보이는 줄에 붙인다.
    func deleteBackward() -> Edit? {
        guard selection.length == 0 else { return nil }
        let i = cursorLine
        let line = index[i]
        guard selection.location <= line.bodyStart else { return nil }
        if line.level > minLevel, line.indentLength > 0 {
            return shiftLines(-1)
        }
        guard i > 0, hidden[i - 1], let pv = previousVisible(i) else { return nil }
        var result = allLines()
        let joinColumn = (result[pv].text as NSString).length
        result[pv].text += index.body(i, text)
        result.remove(at: i)
        return makeEdit(result, select: (pv, joinColumn))
    }

    /// 여러 줄을 붙여넣을 때 붙여넣는 위치의 들여쓰기에 맞춘다.
    static func normalizePaste(_ string: String, baseLevel: Int) -> String {
        let lines = string.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard lines.count > 1 else { return string }
        let minLevel = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map(LineText.level).min() ?? 0
        return lines.enumerated().map { k, s in
            let body = String(s.dropFirst(LineText.indentLength(s)))
            let level = LineText.level(s) - minLevel + (k == 0 ? 0 : baseLevel)
            return String(repeating: "\t", count: max(level, 0)) + body
        }.joined(separator: "\n")
    }
}

// MARK: - 숨김

/// 접기·포커스·호이스트·필터를 합쳐 숨길 줄을 계산한다.
struct Visibility {
    /// 이 항목의 자손만 보인다(항목 자신은 숨김)
    var hoistedID: Int?
    /// 이 항목과 자손만 보인다(항목은 펼친 상태로)
    var focusedID: Int?
    /// 필터 결과에서 숨긴 줄 id. nil이면 필터 없음
    var filterHiddenIDs: Set<Int>?

    func hidden(_ index: LineIndex) -> [Bool] {
        let n = index.count
        var hidden = Array(repeating: false, count: n)
        var scope = 0..<n
        var focused = -1
        if let id = focusedID, let f = index.lines.firstIndex(where: { $0.id == id }) {
            scope = f..<index[f].branchEnd
            focused = f
        } else if let id = hoistedID, let h = index.lines.firstIndex(where: { $0.id == id }) {
            scope = (h + 1)..<index[h].branchEnd
        }
        var hiddenUntil = -1
        for i in 0..<n {
            if !scope.contains(i) { hidden[i] = true; continue }
            if let ids = filterHiddenIDs {
                hidden[i] = ids.contains(index[i].id)
                continue
            }
            if i < hiddenUntil { hidden[i] = true; continue }
            if index[i].collapsed, i != focused, index.hasChildren(i) { hiddenUntil = index[i].branchEnd }
        }
        return hidden
    }

    /// 필터 결과(일치 항목과 조상)에 들지 않는 줄 id.
    static func filterHiddenIDs(_ index: LineIndex, matches: [Int]) -> Set<Int> {
        var visible = Array(repeating: false, count: index.count)
        for m in matches {
            var k = m
            while k >= 0, !visible[k] { visible[k] = true; k = index[k].parent }
        }
        var ids = Set<Int>()
        for i in 0..<index.count where !visible[i] { ids.insert(index[i].id) }
        return ids
    }
}
