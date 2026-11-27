import AppKit

/// 개요 편집 텍스트 뷰. 손잡이 그리기·클릭·끌기, 키 동작, 메뉴 명령을 맡는다.
final class OutlineTextView: NSTextView {
    unowned var editor: OutlineEditor!
    private var dropIndicator: NSRect?

    var controller: DocumentWindowController? { window?.windowController as? DocumentWindowController }

    /// 포커스·호이스트한 깊이만큼 글을 왼쪽으로 당긴다.
    var levelShift: CGFloat = 0 {
        didSet { if levelShift != oldValue { needsDisplay = true; window?.invalidateCursorRects(for: self) } }
    }

    override var textContainerOrigin: NSPoint {
        let o = super.textContainerOrigin
        return NSPoint(x: o.x - levelShift, y: o.y)
    }
    private var index: LineIndex { editor.index }

    // MARK: - 키

    override func insertNewline(_ sender: Any?) {
        if let edit = editor.snapshot().insertNewline() { editor.apply(edit) } else { super.insertNewline(sender) }
    }

    override func insertNewlineIgnoringFieldEditor(_ sender: Any?) { super.insertNewline(sender) }
    override func insertTab(_ sender: Any?) { editor.perform { $0.shiftLines(1) } }
    override func insertBacktab(_ sender: Any?) { editor.perform { $0.shiftLines(-1) } }

    override func deleteBackward(_ sender: Any?) {
        if let edit = editor.snapshot().deleteBackward() { editor.apply(edit) } else { super.deleteBackward(sender) }
    }

    override func paste(_ sender: Any?) {
        guard let s = NSPasteboard.general.string(forType: .string), s.contains("\n") else { return pasteAsPlainText(sender) }
        let level = index[editor.cursorLine].level
        insertText(EditorSnapshot.normalizePaste(s, baseLevel: level), replacementRange: selectedRange())
    }

    // MARK: - 손잡이 그리기

    private var handleSize: CGFloat { (editor.styler.baseFont.pointSize * 0.4).rounded() }

    /// 본문 왼쪽의 손잡이 위치. 숨은 줄·빈 줄은 nil.
    func handleRect(forLine i: Int) -> NSRect? {
        guard let lm = layoutManager, i < index.count, !editor.hidden[i], !index[i].isBlank else { return nil }
        let line = index[i]
        guard line.bodyStart < textStorage!.length else { return nil }
        let g = lm.glyphIndexForCharacter(at: line.bodyStart)
        let fragment = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
        let location = lm.location(forGlyphAt: g)
        let origin = textContainerOrigin
        let font = editor.styler.baseFont
        let size = handleSize
        let gap: CGFloat = (font.pointSize * 0.45).rounded()
        let bodyX: CGFloat = origin.x + fragment.minX + location.x
        let baseline: CGFloat = origin.y + fragment.minY + location.y
        let x: CGFloat = bodyX - size - gap
        let y: CGFloat = baseline - font.xHeight / 2 - size / 2
        return NSRect(x: x, y: y, width: size, height: size)
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let lm = layoutManager, let tc = textContainer, index.count > 0 else { return }
        let origin = textContainerOrigin
        let glyphs = lm.glyphRange(forBoundingRect: rect.offsetBy(dx: -origin.x, dy: -origin.y), in: tc)
        let chars = lm.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        var i = index.line(at: chars.location)
        let end = NSMaxRange(chars)
        while i < index.count, index[i].start <= end {
            if let r = handleRect(forLine: i) { drawHandle(r, line: i) }
            i += 1
        }
        if let d = dropIndicator {
            NSColor.controlAccentColor.setFill()
            d.fill()
        }
    }

    private func drawHandle(_ r: NSRect, line i: Int) {
        let base = editor.styler.theme.handle ?? editor.styler.textColor
        let parent = index.hasChildren(i)
        if parent, index[i].collapsed || editor.visibility.filterHiddenIDs != nil && hasHiddenChild(i) {
            base.withAlphaComponent(0.3).setFill()
            NSBezierPath(ovalIn: r.insetBy(dx: -r.width * 0.45, dy: -r.height * 0.45)).fill()
            base.setFill()
        } else {
            base.withAlphaComponent(parent ? 0.55 : 0.22).setFill()
        }
        NSBezierPath(ovalIn: r).fill()
    }

    private func hasHiddenChild(_ i: Int) -> Bool {
        index.children(i).contains { editor.hidden[$0] }
    }

    // MARK: - 마우스

    private func characterIndex(at p: NSPoint) -> Int? {
        guard let lm = layoutManager, let tc = textContainer, textStorage!.length > 0 else { return nil }
        let point = NSPoint(x: p.x - textContainerOrigin.x, y: p.y - textContainerOrigin.y)
        var fraction: CGFloat = 0
        let c = lm.characterIndex(for: point, in: tc, fractionOfDistanceBetweenInsertionPoints: &fraction)
        return c < textStorage!.length ? c : nil
    }

    private func visibleLine(at p: NSPoint) -> Int? {
        guard let c = characterIndex(at: p) else { return index.count > 0 ? index.count - 1 : nil }
        let i = index.line(at: c)
        return editor.hidden[i] ? editor.previousVisible(i) : i
    }

    private func handleLine(at p: NSPoint) -> Int? {
        guard let i = visibleLine(at: p), let r = handleRect(forLine: i) else { return nil }
        let hit = NSRect(x: r.minX - 6, y: r.minY - 6, width: r.width + 12, height: r.height + 12)
        return hit.contains(p) ? i : nil
    }

    /// 문자 범위가 그려진 사각형(뷰 좌표).
    private func rect(forCharacters r: NSRange) -> NSRect {
        guard let lm = layoutManager, let tc = textContainer else { return .zero }
        let g = lm.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
        return lm.boundingRect(forGlyphRange: g, in: tc).offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }

    /// 작업 앞 `- ` 영역. 클릭하면 @done 토글.
    func dashRect(forLine i: Int) -> NSRect? {
        guard i < index.count, !editor.hidden[i], index[i].type == .task else { return nil }
        return rect(forCharacters: NSRange(location: index[i].bodyStart, length: 2)).insetBy(dx: -4, dy: -2)
    }

    private func dashLine(at p: NSPoint) -> Int? {
        guard let i = visibleLine(at: p), let r = dashRect(forLine: i) else { return nil }
        return r.contains(p) ? i : nil
    }

    /// 점이 실제 글자 위에 있을 때만 그 글자 위치. 줄 끝 빈 곳 클릭은 nil.
    private func characterUnder(_ p: NSPoint) -> Int? {
        guard let c = characterIndex(at: p) else { return nil }
        return rect(forCharacters: NSRange(location: c, length: 1)).insetBy(dx: -1, dy: -1).contains(p) ? c : nil
    }

    private enum Hit { case link(String), tag(String), tagValue(String, String) }

    private func hit(at p: NSPoint) -> Hit? {
        guard let c = characterUnder(p), let storage = textStorage else { return nil }
        if let link = storage.attribute(.outlineLink, at: c, effectiveRange: nil) as? String { return .link(link) }
        guard let tag = storage.attribute(.outlineTag, at: c, effectiveRange: nil) as? String else { return nil }
        if let value = storage.attribute(.outlineTagValue, at: c, effectiveRange: nil) as? String { return .tagValue(tag, value) }
        return .tag(tag)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let i = handleLine(at: p) {
            // ⌥클릭은 그 항목에 포커스
            if event.modifierFlags.contains(.option) { editor.focus(line: i) } else { trackHandle(i) }
            return
        }
        if event.clickCount == 1, event.modifierFlags.intersection([.shift, .control, .option]).isEmpty {
            if let i = dashLine(at: p) {
                editor.toggleDone(line: i)
                return
            }
            switch hit(at: p) {
            case let .link(link)?: open(link); return
            case let .tag(name)?: editor.onTagClicked?("@" + name); return
            case let .tagValue(name, value)?:
                let quoted = "\"" + value.replacingOccurrences(of: "\"", with: "\\\"") + "\""
                editor.onTagClicked?(value.contains(",") ? "@\(name) contains[l] \(quoted)" : "@\(name) = \(quoted)")
                return
            case nil: break
            }
        }
        super.mouseDown(with: event)
    }

    private func open(_ link: String) {
        if link.hasPrefix("/") || link.hasPrefix("~") || link.hasPrefix(".") {
            let path = (link.replacingOccurrences(of: "\\ ", with: " ") as NSString).expandingTildeInPath
            let base = controller?.document?.fileURL?.deletingLastPathComponent()
            let url = link.hasPrefix(".") && base != nil ? URL(fileURLWithPath: path, relativeTo: base) : URL(fileURLWithPath: path)
            NSWorkspace.shared.open(url)
        } else if let url = URL(string: link) {
            NSWorkspace.shared.open(url)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if handleLine(at: p) != nil || dashLine(at: p) != nil || hit(at: p) != nil {
            NSCursor.pointingHand.set()
        } else {
            super.mouseMoved(with: event)
        }
    }

    // MARK: - 접근성: 손잡이·대시를 버튼으로 노출한다

    private weak var accessibilityHost: NSView?
    /// 접근성 클라이언트가 나중에 묻기 때문에 만든 요소를 붙잡아 둔다
    private var accessibilityCache: [ActionElement] = []

    private nonisolated final class ActionElement: NSAccessibilityElement {
        nonisolated(unsafe) var action: @MainActor () -> Void = {}
        override func accessibilityPerformPress() -> Bool {
            let run = action
            MainActor.assumeIsolated { run() }
            return true
        }
    }

    /// 보이는 줄의 대시·태그·손잡이 버튼. `parent` 좌표로 바꿔 둔다.
    func outlineAccessibilityElements(in parent: NSView) -> [Any] {
        var children: [ActionElement] = []
        defer { accessibilityCache = children }
        accessibilityHost = parent
        guard let lm = layoutManager, let tc = textContainer, index.count > 0 else { return children }
        let origin = textContainerOrigin
        let glyphs = lm.glyphRange(forBoundingRect: visibleRect.offsetBy(dx: -origin.x, dy: -origin.y), in: tc)
        let chars = lm.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        var i = index.line(at: chars.location)
        while i < index.count, index[i].start <= NSMaxRange(chars) {
            let name = index.displayName(i, editor.text)
            let line = i
            if let r = dashRect(forLine: i) {
                children.append(element(r, label: "완료 \(name)", identifier: "dash-\(i)") { [weak self] in self?.editor.toggleDone(line: line) })
            }
            for tag in index[i].tags {
                let r = rect(forCharacters: NSRange(location: index[i].start + tag.range.location, length: tag.range.length))
                children.append(element(r, label: "태그 @\(tag.name)", identifier: "tag-\(i)-\(tag.name)") { [weak self] in self?.editor.onTagClicked?("@" + tag.name) })
            }
            if index.hasChildren(i), let r = handleRect(forLine: i) {
                children.append(element(r.insetBy(dx: -4, dy: -4), label: "접기 \(name)", identifier: "handle-\(i)") { [weak self] in self?.editor.toggleFold([line]) })
            }
            i += 1
        }
        return children
    }

    private func element(_ r: NSRect, label: String, identifier: String, action: @escaping @MainActor () -> Void) -> ActionElement {
        let e = ActionElement()
        e.setAccessibilityRole(.button)
        e.setAccessibilityLabel(label)
        e.setAccessibilityIdentifier(identifier)
        e.setAccessibilityParent(accessibilityHost)
        if let window { e.setAccessibilityFrame(window.convertToScreen(convert(r, to: nil))) }
        e.action = action
        return e
    }

    // MARK: - 태그 자동 완성

    private lazy var tagPopup: TagCompletionPopup = {
        let p = TagCompletionPopup()
        p.onAccept = { [weak self] name, range in
            guard let self else { return }
            self.insertText(name, replacementRange: range)
        }
        return p
    }()

    /// 커서가 `@이름` 안에 있으면 `@` 다음부터 커서까지의 범위.
    private var tagPrefixRange: NSRange? {
        let sel = selectedRange()
        guard sel.length == 0, !hasMarkedText() else { return nil }
        let s = string as NSString
        var k = sel.location
        let nameChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._"))
        while k > 0, let u = UnicodeScalar(s.character(at: k - 1)), nameChars.contains(u) { k -= 1 }
        guard k > 0, s.character(at: k - 1) == 64 else { return nil }
        // `@` 앞은 줄 시작이나 공백이어야 태그다
        if k >= 2, let before = UnicodeScalar(s.character(at: k - 2)), !CharacterSet.whitespacesAndNewlines.contains(before) { return nil }
        return NSRange(location: k, length: sel.location - k)
    }

    private func updateTagCompletion() {
        guard let range = tagPrefixRange, let window else { tagPopup.hide(); return }
        let prefix = (string as NSString).substring(with: range).lowercased()
        var names = Set(editor.index.lines.flatMap { $0.tags.map(\.name) })
        names.formUnion(GlobalConfig.shared.tags.include)
        names.formUnion(["done", "today", "due", "start"])
        let matches = names.filter { $0.lowercased().hasPrefix(prefix) && $0.lowercased() != prefix }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        guard !matches.isEmpty else { tagPopup.hide(); return }
        let caret = firstRect(forCharacterRange: NSRange(location: range.location - 1, length: 1), actualRange: nil)
        tagPopup.show(matches, range: range, below: caret, in: window)
    }

    override func didChangeText() {
        super.didChangeText()
        updateTagCompletion()
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        // 커서가 태그 밖으로 나가면 닫는다
        if tagPopup.isVisible, tagPrefixRange == nil { tagPopup.hide() }
    }

    override func doCommand(by selector: Selector) {
        if tagPopup.isVisible {
            switch selector {
            case #selector(moveUp(_:)): tagPopup.move(-1); return
            case #selector(moveDown(_:)): tagPopup.move(1); return
            case #selector(insertNewline(_:)), #selector(insertTab(_:)): tagPopup.accept(); return
            case #selector(cancelOperation(_:)): tagPopup.hide(); return
            default: tagPopup.hide()
            }
        }
        super.doCommand(by: selector)
    }

    override func resignFirstResponder() -> Bool {
        tagPopup.hide()
        return super.resignFirstResponder()
    }

    // MARK: - 끌어놓기

    private func trackHandle(_ source: Int) {
        guard let window else { return }
        var dragging = false
        let start = NSEvent.mouseLocation
        var target: (before: Int, level: Int)?
        while let e = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if e.type == .leftMouseUp { break }
            let now = NSEvent.mouseLocation
            if !dragging, hypot(now.x - start.x, now.y - start.y) > 4 { dragging = true }
            guard dragging else { continue }
            autoscroll(with: e)
            target = dropTarget(at: convert(e.locationInWindow, from: nil), source: source)
            needsDisplay = true
        }
        dropIndicator = nil
        needsDisplay = true
        if !dragging {
            editor.toggleFold([source])
        } else if let target, let edit = editor.snapshot().moveBranch(source, before: target.before, level: target.level) {
            editor.apply(edit)
        }
    }

    private func dropTarget(at p: NSPoint, source: Int) -> (before: Int, level: Int)? {
        guard let lm = layoutManager, let i = visibleLine(at: p) else { dropIndicator = nil; return nil }
        let g = lm.glyphIndexForCharacter(at: min(index[i].start, max(textStorage!.length - 1, 0)))
        let fragment = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil).offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        var before: Int
        var y: CGFloat
        if p.y < fragment.midY {
            before = i
            y = fragment.minY
        } else {
            // 접힌 가지는 통째로 건너뛴다
            var k = i + 1
            while k < index.count, editor.hidden[k] { k += 1 }
            before = k
            y = fragment.maxY
        }
        let prev = editor.snapshot().previousVisible(before)
        if before > source, before < index[source].branchEnd { dropIndicator = nil; return nil }
        let maxLevel = prev.map { index[$0].level + 1 } ?? 0
        let indent = editor.styler.indentWidth
        let x0 = textContainerOrigin.x + (textContainer?.lineFragmentPadding ?? 0)
        let level = min(max(Int(((p.x - x0) / indent).rounded(.down)), 0), maxLevel)
        dropIndicator = NSRect(x: x0 + CGFloat(level) * indent, y: y - 1, width: bounds.width - x0 - CGFloat(level) * indent - 8, height: 2)
        if prev == source || before == source { before = source }
        return (before, level)
    }

    // MARK: - 메뉴 명령: 항목

    @objc func newTask(_ sender: Any?) { editor.perform { $0.insertItem("- 새 작업", selectFrom: 2, selectTo: 6) } }
    @objc func newNote(_ sender: Any?) { editor.perform { $0.insertItem("새 메모", selectFrom: 0, selectTo: 4) } }
    @objc func newProject(_ sender: Any?) { editor.perform { $0.insertItem("새 프로젝트:", selectFrom: 0, selectTo: 6) } }
    @objc func groupLines(_ sender: Any?) { editor.perform { $0.groupLines() } }
    @objc func duplicateLines(_ sender: Any?) { editor.perform { $0.duplicateLines() } }
    @objc func deleteLines(_ sender: Any?) { editor.perform { $0.deleteLines() } }
    @objc func formatProject(_ sender: Any?) { editor.perform { $0.format(as: .project) } }
    @objc func formatTask(_ sender: Any?) { editor.perform { $0.format(as: .task) } }
    @objc func formatNote(_ sender: Any?) { editor.perform { $0.format(as: .note) } }
    @objc func moveLineRight(_ sender: Any?) { editor.perform { $0.shiftLines(1) } }
    @objc func moveLineLeft(_ sender: Any?) { editor.perform { $0.shiftLines(-1) } }
    @objc func moveLineUp(_ sender: Any?) { editor.perform { $0.moveLines(up: true) } }
    @objc func moveLineDown(_ sender: Any?) { editor.perform { $0.moveLines(up: false) } }
    @objc func moveBranchesRight(_ sender: Any?) { editor.perform { $0.shiftBranches(1) } }
    @objc func moveBranchesLeft(_ sender: Any?) { editor.perform { $0.shiftBranches(-1) } }
    @objc func moveBranchesUp(_ sender: Any?) { editor.perform { $0.moveBranches(up: true) } }
    @objc func moveBranchesDown(_ sender: Any?) { editor.perform { $0.moveBranches(up: false) } }
    @objc func moveToProject(_ sender: Any?) { controller?.showMoveToProject() }

    // MARK: 태그

    @objc func tagWith(_ sender: Any?) { controller?.showTagWith() }
    @objc func toggleDone(_ sender: Any?) { editor.toggleDone() }
    @objc func toggleToday(_ sender: Any?) { editor.perform { $0.toggleTag("today") } }
    @objc func toggleDue(_ sender: Any?) { toggleDateTag("due", title: "마감일") }
    @objc func toggleStart(_ sender: Any?) { toggleDateTag("start", title: "시작일") }
    @objc func clearTags(_ sender: Any?) { editor.perform { $0.clearTags() } }

    /// 예상 뽀모도로 수(@estimate)를 1–10 중에서 고른다.
    @objc func setPomodoroEstimate(_ sender: Any?) {
        guard let window else { return }
        let choices = (1...10).map { n in
            PaletteChoice(title: "🍅 \(n)", detail: "@estimate(\(n))") { [weak self] in
                self?.editor.perform { $0.setTag("estimate", value: String(n), remove: false) }
            }
        } + [PaletteChoice(title: "예상 지우기", symbol: "xmark") { [weak self] in
            self?.editor.perform { $0.setTag("estimate", value: nil, remove: true) }
        }]
        ChoicePalette.show(over: window, placeholder: "예상 뽀모도로", choices: choices)
    }

    @objc func archiveDone(_ sender: Any?) {
        editor.perform { $0.archiveDone(addProjectTag: Preferences.archiveAddsProject, removeExtraTags: Preferences.archiveRemovesTags) }
    }

    func toggleDateTag(_ name: String, title: String) {
        if editor.snapshot().hasTag(name) {
            editor.perform { $0.setTag(name, value: nil, remove: true) }
            return
        }
        let selection = selectedRange()
        controller?.askDate(title: title) { [weak self] date in
            guard let self, let date else { return }
            self.setSelectedRange(selection)
            self.editor.perform { $0.setTag(name, value: date, remove: false) }
        }
    }

    @objc func insertDate(_ sender: Any?) {
        let selection = selectedRange()
        controller?.askDate(title: "날짜 넣기") { [weak self] date in
            guard let self, let date else { return }
            self.setSelectedRange(selection)
            self.insertText(date, replacementRange: selection)
        }
    }

    // MARK: 개요

    @objc func goHome(_ sender: Any?) { editor.goHome() }
    @objc func focusIn(_ sender: Any?) { editor.focusIn() }
    @objc func focusOut(_ sender: Any?) { editor.focusOut() }
    @objc func expandItems(_ sender: Any?) { editor.expand(completely: false) }
    @objc func expandItemsCompletely(_ sender: Any?) { editor.expand(completely: true) }
    @objc func collapseItems(_ sender: Any?) { editor.collapse(completely: false) }
    @objc func collapseItemsCompletely(_ sender: Any?) { editor.collapse(completely: true) }
    @objc func increaseExpansionLevel(_ sender: Any?) { editor.increaseExpansionLevel() }
    @objc func decreaseExpansionLevel(_ sender: Any?) { editor.decreaseExpansionLevel() }
    @objc func expandAll(_ sender: Any?) { editor.setAllCollapsed(false) }
    @objc func collapseAll(_ sender: Any?) { editor.setAllCollapsed(true) }

    // MARK: 선택·복사

    @objc func selectBranch(_ sender: Any?) { editor.selectBranch() }
    @objc func selectItem(_ sender: Any?) { editor.selectItem() }
    @objc func selectSentence(_ sender: Any?) { editor.selectSentence() }
    @objc func expandSelection(_ sender: Any?) { editor.expandSelection() }
    @objc func contractSelection(_ sender: Any?) { editor.contractSelection() }

    @objc func copyDisplayed(_ sender: Any?) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(editor.displayedText(in: selectedRange()), forType: .string)
    }

    // MARK: 확대

    @objc func zoomIn(_ sender: Any?) { setZoom(editor.styler.scale * 1.1) }
    @objc func zoomOut(_ sender: Any?) { setZoom(editor.styler.scale / 1.1) }
    @objc func zoomToActualSize(_ sender: Any?) { setZoom(1) }

    private func setZoom(_ scale: CGFloat) {
        editor.styler.scale = min(max(scale, 0.5), 4)
        editor.restyleAll()
        needsDisplay = true
    }

    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleDone(_:)): item.state = editor.snapshot().hasTag("done") ? .on : .off
        case #selector(toggleToday(_:)): item.state = editor.snapshot().hasTag("today") ? .on : .off
        case #selector(toggleDue(_:)): item.state = editor.snapshot().hasTag("due") ? .on : .off
        case #selector(toggleStart(_:)): item.state = editor.snapshot().hasTag("start") ? .on : .off
        case #selector(focusOut(_:)): return editor.focusedLine != nil || editor.hoistedLine != nil
        default: break
        }
        return super.validateMenuItem(item)
    }
}

/// 편집기 스크롤 뷰. 텍스트 뷰의 대시·태그·손잡이를 접근성 버튼으로 노출한다.
final class OutlineScrollView: NSScrollView {
    override func accessibilityChildren() -> [Any]? {
        let base = super.accessibilityChildren() ?? []
        guard let tv = documentView as? OutlineTextView else { return base }
        return base + tv.outlineAccessibilityElements(in: self)
    }
}
