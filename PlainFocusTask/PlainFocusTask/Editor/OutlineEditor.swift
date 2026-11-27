import AppKit

/// 문서 하나의 편집 상태. 텍스트(원본), 줄 색인, 접기·포커스·필터 숨김, 서식을 묶는다.
final class OutlineEditor: NSObject {
    let storage = NSTextStorage()
    let layoutManager = NSLayoutManager()
    let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
    private(set) var index: LineIndex
    private(set) var hidden: [Bool] = []
    private var hiddenIDs = Set<Int>()
    private var anyHidden = false
    private(set) var visibility = Visibility()
    private(set) var filterQuery = ""
    var styler = Styler()
    weak var editorView: OutlineTextView?
    /// 텍스트가 바뀌면 호출(사이드바 갱신)
    var onContentChange: (() -> Void)?
    /// 포커스·필터가 바뀌면 호출
    var onStateChange: (() -> Void)?
    /// 태그를 ⌘클릭하면 호출
    var onTagClicked: ((String) -> Void)?
    private var applying = false
    private var selectionStack: [NSRange] = []

    init(text: String) {
        storage.mutableString.setString(text)
        index = LineIndex(storage.mutableString)
        super.init()
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        layoutManager.delegate = self
        layoutManager.allowsNonContiguousLayout = true
        textContainer.widthTracksTextView = true
        storage.delegate = self
        restyleAll()
        recomputeHidden(invalidate: false)
    }

    var text: NSString { storage.mutableString }
    var string: String { storage.string }

    /// 되돌리기·외부 변경으로 문서 전체를 바꾼다.
    func replaceAll(_ newText: String) {
        visibility = Visibility()
        filterQuery = ""
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: newText)
        restyleAll()
        recomputeHidden(invalidate: true)
        onStateChange?()
    }

    func restyleAll() {
        storage.beginEditing()
        styler.style(storage, index, lines: 0...max(index.count - 1, 0))
        storage.endEditing()
        editorView?.typingAttributes = [.font: styler.baseFont, .foregroundColor: NSColor.labelColor,
                                      .paragraphStyle: styler.paragraphStyle(level: 0, type: .note, font: styler.baseFont)]
    }

    // MARK: - 숨김

    func line(withID id: Int) -> Int? { index.lines.firstIndex { $0.id == id } }

    var focusedLine: Int? { visibility.focusedID.flatMap(line(withID:)) }
    var hoistedLine: Int? { visibility.hoistedID.flatMap(line(withID:)) }

    var minLevel: Int {
        if let f = focusedLine { return index[f].level }
        if let h = hoistedLine { return index[h].level + 1 }
        return 0
    }

    /// 숨김을 다시 계산하고 바뀐 줄만 레이아웃을 무효화한다.
    /// - Returns: 숨김 여부가 바뀐 줄 id
    @discardableResult
    func recomputeHidden(invalidate: Bool) -> Set<Int> {
        let new = visibility.hidden(index)
        var ids = Set<Int>()
        for i in 0..<new.count where new[i] { ids.insert(index[i].id) }
        let changed = ids.symmetricDifference(hiddenIDs)
        hidden = new
        hiddenIDs = ids
        anyHidden = !ids.isEmpty
        if invalidate { invalidateLines(changed) }
        return changed
    }

    private func invalidateLines(_ changed: Set<Int>) {
        guard !changed.isEmpty else { return }
        var runStart = -1
        func flush(_ end: Int) {
            guard runStart >= 0 else { return }
            let range = NSRange(location: index[runStart].start, length: index[end - 1].fullEnd - index[runStart].start)
            layoutManager.invalidateGlyphs(forCharacterRange: range, changeInLength: 0, actualCharacterRange: nil)
            layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
            runStart = -1
        }
        for i in 0..<index.count {
            if changed.contains(index[i].id) { if runStart < 0 { runStart = i } } else { flush(i) }
        }
        flush(index.count)
        editorView?.needsDisplay = true
    }

    func isHiddenCharacter(_ c: Int) -> Bool {
        anyHidden && c < storage.length && hidden[index.line(at: c)]
    }

    func previousVisible(_ i: Int) -> Int? { snapshot().previousVisible(i) }
    func nextVisible(_ i: Int) -> Int? { snapshot().nextVisible(i) }

    /// 숨은 줄이나 들여쓰기 안으로 들어간 커서를 보이는 본문으로 옮긴다.
    func adjustSelection(_ r: NSRange, from old: NSRange) -> NSRange {
        guard r.length == 0, index.count > 0 else { return r }
        let i = index.line(at: r.location)
        let line = index[i]
        let backward = r.location < old.location
        if hidden[i] {
            if backward, let p = previousVisible(i) { return NSRange(location: index[p].end, length: 0) }
            if let v = nextVisible(i) { return NSRange(location: index[v].bodyStart, length: 0) }
            if let p = previousVisible(i) { return NSRange(location: index[p].end, length: 0) }
            return r
        }
        if r.location < line.bodyStart {
            if backward, old.location == line.bodyStart, let p = previousVisible(i) { return NSRange(location: index[p].end, length: 0) }
            return NSRange(location: line.bodyStart, length: 0)
        }
        return r
    }

    // MARK: - 명령 적용

    var selection: NSRange { editorView?.selectedRange() ?? NSRange(location: 0, length: 0) }

    var cursorLine: Int { index.line(at: selection.location) }

    func snapshot(selection: NSRange? = nil) -> EditorSnapshot {
        EditorSnapshot(text: text, index: index, hidden: hidden, selection: selection ?? self.selection, minLevel: minLevel)
    }

    func perform(_ command: (EditorSnapshot) -> Edit?) {
        guard let edit = command(snapshot()) else { NSSound.beep(); return }
        apply(edit)
    }

    /// 편집 계획을 `NSTextView` 경로로 적용한다. 실행 취소가 자동으로 기록된다.
    func apply(_ edit: Edit, keepSelection: Bool = false) {
        guard let tv = editorView else { return }
        let old = tv.selectedRange()
        guard tv.shouldChangeText(in: edit.range, replacementString: edit.text) else { return }
        applying = true
        storage.replaceCharacters(in: edit.range, with: edit.text)
        index.carry(startingAt: edit.firstLine, from: edit.carry)
        for id in edit.expandIDs { if let i = line(withID: id) { index.setCollapsed(i, false) } }
        tv.didChangeText()
        recomputeHidden(invalidate: true)
        if keepSelection {
            let delta = (edit.text as NSString).length - edit.range.length
            tv.setSelectedRange(old.location > edit.range.location ? NSRange(location: max(old.location + delta, 0), length: old.length) : old)
        } else {
            tv.setSelectedRange(edit.selection)
            tv.scrollRangeToVisible(edit.selection)
        }
        applying = false
    }

    // MARK: - 태그

    static var today: String { DateParser.format(DateParser.calendar.startOfDay(for: .now)) }

    func toggleDone(line: Int? = nil) {
        let value = Preferences.includeDateWhenDone ? Self.today : nil
        if let line {
            let snap = snapshot(selection: NSRange(location: index[line].bodyStart, length: 0))
            if let edit = snap.toggleTag("done", value: value) { apply(edit, keepSelection: true) }
        } else {
            perform { $0.toggleTag("done", value: value) }
        }
    }

    // MARK: - 접기

    private var selectedVisible: [Int] { snapshot().visibleSelected }

    private func afterFoldChange() {
        recomputeHidden(invalidate: true)
        guard let tv = editorView else { return }
        let i = cursorLine
        if hidden[i] {
            var k = i
            while k >= 0, hidden[k] { k = index[k].parent }
            if k >= 0 { tv.setSelectedRange(NSRange(location: index[k].end, length: 0)) }
        }
        tv.scrollRangeToVisible(tv.selectedRange())
    }

    func setCollapsed(_ items: [Int], _ value: Bool, completely: Bool) {
        for i in items {
            let end = completely ? index[i].branchEnd : i + 1
            for k in i..<end where index.hasChildren(k) { index.setCollapsed(k, value) }
        }
        afterFoldChange()
    }

    /// 손잡이 클릭: 펼쳐져 있으면 접고, 아니면 편다.
    func toggleFold(_ items: [Int]? = nil, completely: Bool = false) {
        let parents = index.commonAncestors(items ?? selectedVisible).filter { index.hasChildren($0) }
        guard !parents.isEmpty else { return }
        let allExpanded = parents.allSatisfy { !index[$0].collapsed }
        setCollapsed(parents, allExpanded, completely: completely)
    }

    func expand(completely: Bool) {
        var parents = index.commonAncestors(selectedVisible).filter { index.hasChildren($0) }
        if parents.isEmpty, let first = selectedVisible.first, index[first].parent >= 0 { parents = [index[first].parent] }
        setCollapsed(parents, false, completely: completely)
    }

    func collapse(completely: Bool) {
        let parents = index.commonAncestors(selectedVisible).filter { index.hasChildren($0) }
        if parents.isEmpty {
            guard let first = selectedVisible.first, index[first].parent >= 0 else { return }
            let p = index[first].parent
            editorView?.setSelectedRange(NSRange(location: index[p].end, length: 0))
            setCollapsed([p], true, completely: completely)
            return
        }
        setCollapsed(parents, true, completely: completely)
    }

    private var expansionLevel: Int {
        var minCollapsed = Int.max, maxParent = -1
        for i in 0..<index.count where !hidden[i] && index.hasChildren(i) {
            maxParent = max(maxParent, index[i].depth)
            if index[i].collapsed { minCollapsed = min(minCollapsed, index[i].depth) }
        }
        return minCollapsed == Int.max ? maxParent + 1 : minCollapsed
    }

    /// 깊이가 `level` 이상인 항목은 접고, 얕은 항목은 편다.
    func setExpansionLevel(_ level: Int) {
        for i in 0..<index.count where index.hasChildren(i) { index.setCollapsed(i, index[i].depth >= level) }
        afterFoldChange()
    }

    func increaseExpansionLevel() { setExpansionLevel(expansionLevel + 1) }
    func decreaseExpansionLevel() { setExpansionLevel(max(expansionLevel - 1, 0)) }

    func setAllCollapsed(_ value: Bool) {
        for i in 0..<index.count where index.hasChildren(i) { index.setCollapsed(i, value) }
        afterFoldChange()
    }

    // MARK: - 포커스·필터

    private func stateChanged() {
        recomputeHidden(invalidate: true)
        if let tv = editorView {
            let i = cursorLine
            if hidden[i], let first = (0..<index.count).first(where: { !hidden[$0] }) {
                tv.setSelectedRange(NSRange(location: index[first].bodyStart, length: 0))
            }
            tv.scrollToBeginningOfDocument(nil)
            tv.scrollRangeToVisible(tv.selectedRange())
        }
        onStateChange?()
    }

    func focus(line: Int?) {
        visibility.focusedID = line.map { index[$0].id }
        visibility.hoistedID = nil
        stateChanged()
    }

    func focusIn() {
        let i = cursorLine
        if focusedLine == i, index.hasChildren(i) {
            visibility.hoistedID = index[i].id
            visibility.focusedID = nil
        } else {
            visibility.focusedID = index[i].id
        }
        stateChanged()
    }

    func focusOut() {
        if let f = focusedLine {
            let p = index[f].parent
            visibility.focusedID = p >= 0 && p != hoistedLine ? index[p].id : nil
        } else if let h = hoistedLine {
            visibility.hoistedID = nil
            visibility.focusedID = index[h].id
        } else {
            return
        }
        stateChanged()
    }

    func goHome() {
        visibility = Visibility()
        filterQuery = ""
        stateChanged()
    }

    /// 편집기 필터를 건다. 잘못된 질의면 오류 문장을 돌려주고 이전 결과를 유지한다.
    @discardableResult
    func setFilter(_ query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            filterQuery = ""
            visibility.filterHiddenIDs = nil
        } else {
            let path = ItemPath(trimmed)
            if let error = path.error { return error }
            filterQuery = trimmed
            visibility.filterHiddenIDs = Visibility.filterHiddenIDs(index, matches: path.evaluate(index, text))
        }
        stateChanged()
        return nil
    }

    func refreshFilter() { setFilter(filterQuery) }

    // MARK: - 선택

    func selectBranch() {
        let lines = snapshot().selectedLines
        let end = lines.map { index[$0].branchEnd }.max()! - 1
        editorView?.setSelectedRange(NSRange(location: index[lines.lowerBound].bodyStart, length: index[end].end - index[lines.lowerBound].bodyStart))
    }

    func selectItem() {
        let lines = snapshot().selectedLines
        editorView?.setSelectedRange(NSRange(location: index[lines.lowerBound].bodyStart, length: index[lines.upperBound].end - index[lines.lowerBound].bodyStart))
    }

    /// 단어 → 항목 → 가지 → 부모 가지 순으로 선택을 넓힌다.
    func expandSelection() {
        guard let tv = editorView else { return }
        let r = tv.selectedRange()
        selectionStack.append(r)
        if r.length == 0 { tv.selectWord(nil); if tv.selectedRange().length > 0 { return } }
        let lines = snapshot().selectedLines
        let a = lines.lowerBound
        let item = NSRange(location: index[a].bodyStart, length: index[lines.upperBound].end - index[a].bodyStart)
        if NSIntersectionRange(item, r) != item || r.length < item.length { tv.setSelectedRange(item); return }
        let end = lines.map { index[$0].branchEnd }.max()! - 1
        let branch = NSRange(location: index[a].bodyStart, length: index[end].end - index[a].bodyStart)
        if branch.length > r.length { tv.setSelectedRange(branch); return }
        let p = index[a].parent
        guard p >= 0 else { tv.selectAll(nil); return }
        tv.setSelectedRange(NSRange(location: index[p].bodyStart, length: index[index[p].branchEnd - 1].end - index[p].bodyStart))
    }

    func contractSelection() {
        guard let r = selectionStack.popLast() else { return }
        editorView?.setSelectedRange(r)
    }

    func selectSentence() {
        guard let tv = editorView else { return }
        let loc = tv.selectedRange().location
        let line = index[index.line(at: loc)]
        text.enumerateSubstrings(in: line.range, options: .bySentences) { _, range, _, stop in
            if NSLocationInRange(loc, range) || NSMaxRange(range) == loc {
                tv.setSelectedRange(range)
                stop.pointee = true
            }
        }
    }

    // MARK: - 출력

    /// 보이는 줄만 모은 텍스트. 표시된 항목 복사에 쓴다.
    func displayedText(in range: NSRange) -> String {
        let lines = snapshot(selection: range).selectedLines.filter { !hidden[$0] }
        return lines.map { text.substring(with: index[$0].range) }.joined(separator: "\n")
    }

    /// 보이는 줄만 담은 서식 문자열. 인쇄에 쓴다.
    func displayedAttributedString() -> NSAttributedString {
        let result = NSMutableAttributedString()
        for i in 0..<index.count where !hidden[i] {
            result.append(storage.attributedSubstring(from: index[i].fullRange))
        }
        return result
    }

    // MARK: - 상태 저장

    nonisolated struct SavedState: Codable, Sendable {
        var collapsed: [Int]
        var focused: Int?
        var hoisted: Int?
    }

    var savedState: SavedState {
        SavedState(collapsed: (0..<index.count).filter { index[$0].collapsed }, focused: focusedLine, hoisted: hoistedLine)
    }

    func restore(_ state: SavedState) {
        for i in state.collapsed where i < index.count { index.setCollapsed(i, true) }
        visibility.focusedID = state.focused.flatMap { $0 < index.count ? index[$0].id : nil }
        visibility.hoistedID = state.hoisted.flatMap { $0 < index.count ? index[$0].id : nil }
        recomputeHidden(invalidate: true)
        onStateChange?()
    }
}

// MARK: - 텍스트 저장소: 바뀐 줄만 다시 파싱·서식

extension OutlineEditor: @preconcurrency NSTextStorageDelegate {
    /// 글꼴 대체(fixAttributes) 전에 서식을 입혀야 한글 글꼴이 바르게 대체된다.
    func textStorage(_ textStorage: NSTextStorage, willProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        index.update(textStorage.mutableString, editedRange: editedRange, delta: delta)
        let a = index.line(at: editedRange.location), b = index.line(at: NSMaxRange(editedRange))
        styler.style(textStorage, index, lines: a...b)
        // 편집 중에는 레이아웃을 건드리지 않고, 바뀐 숨김은 다음 순간 반영한다
        let changed = recomputeHidden(invalidate: false)
        if !changed.isEmpty {
            DispatchQueue.main.async { [weak self] in self?.invalidateLines(changed) }
        }
        if let view = editorView { view.setNeedsDisplay(view.visibleRect) }
        onContentChange?()
    }
}

// MARK: - 레이아웃: 숨긴 줄은 빈 글리프와 높이 0

extension OutlineEditor: @preconcurrency NSLayoutManagerDelegate {
    func layoutManager(_ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>, properties props: UnsafePointer<NSLayoutManager.GlyphProperty>, characterIndexes charIndexes: UnsafePointer<Int>, font aFont: NSFont, forGlyphRange glyphRange: NSRange) -> Int {
        guard anyHidden, glyphRange.length > 0 else { return 0 }
        var properties = Array(UnsafeBufferPointer(start: props, count: glyphRange.length))
        var changed = false
        var lineEnd = -1
        var lineHidden = false
        for k in 0..<glyphRange.length {
            let c = charIndexes[k]
            if c >= lineEnd || lineEnd < 0 {
                let i = index.line(at: c)
                lineEnd = index[i].fullEnd
                if lineEnd <= c { lineEnd = c + 1 }
                lineHidden = hidden[i]
            }
            if lineHidden, !properties[k].contains(.controlCharacter) {
                properties[k] = .null
                changed = true
            }
        }
        guard changed else { return 0 }
        properties.withUnsafeBufferPointer {
            layoutManager.setGlyphs(glyphs, properties: $0.baseAddress!, characterIndexes: charIndexes, font: aFont, forGlyphRange: glyphRange)
        }
        return glyphRange.length
    }

    func layoutManager(_ layoutManager: NSLayoutManager, shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>, lineFragmentUsedRect: UnsafeMutablePointer<NSRect>, baselineOffset: UnsafeMutablePointer<CGFloat>, in textContainer: NSTextContainer, forGlyphRange glyphRange: NSRange) -> Bool {
        guard anyHidden else { return false }
        let c = layoutManager.characterIndexForGlyph(at: glyphRange.location)
        guard isHiddenCharacter(c) else { return false }
        lineFragmentRect.pointee.size.height = 0
        lineFragmentUsedRect.pointee.size.height = 0
        baselineOffset.pointee = 0
        return true
    }
}

// MARK: - 텍스트 뷰: 커서 보정

extension OutlineEditor: NSTextViewDelegate {
    func textView(_ textView: NSTextView, willChangeSelectionFromCharacterRanges oldSelectedCharRanges: [NSValue], toCharacterRanges newSelectedCharRanges: [NSValue]) -> [NSValue] {
        guard !applying else { return newSelectedCharRanges }
        let old = oldSelectedCharRanges.first?.rangeValue ?? NSRange(location: 0, length: 0)
        return newSelectedCharRanges.map { NSValue(range: adjustSelection($0.rangeValue, from: old)) }
    }
}
