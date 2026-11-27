import AppKit
import SwiftUI

/// 문서 창: 사이드바 + 편집기 + 툴바 검색 필드.
final class DocumentWindowController: NSWindowController, NSToolbarDelegate, NSSearchFieldDelegate, NSMenuItemValidation {
    let editor: OutlineEditor
    let textView: OutlineTextView
    private let sidebar = SidebarViewController()
    private let split = NSSplitViewController()
    private var searchField: NSSearchField?
    private var sidebarTimer: Timer?
    private var sections: (home: SidebarItem, projects: SidebarItem, searches: SidebarItem, tags: SidebarItem)?

    init(editor: OutlineEditor) {
        self.editor = editor
        textView = OutlineTextView(frame: .zero, textContainer: editor.textContainer)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 680),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.tabbingIdentifier = "PlainFocusTask"
        window.acceptsMouseMovedEvents = true
        window.setFrameAutosaveName("PlainFocusTaskDocument")
        super.init(window: window)
        setUpEditor()
        setUpSplit()
        setUpToolbar()
        editor.onContentChange = { [weak self] in self?.scheduleSidebarReload() }
        editor.onStateChange = { [weak self] in self?.syncState() }
        editor.onTagClicked = { [weak self] query in self?.applyFilter(query) }
        NotificationCenter.default.addObserver(self, selector: #selector(pomodoroPresentationChanged), name: PomodoroController.presentationChanged, object: nil)
        reloadSidebar()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setUpEditor() {
        let tv = textView
        tv.editor = editor
        tv.delegate = editor
        editor.editorView = tv
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.textContainerInset = NSSize(width: 28, height: 24)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.drawsBackground = true
        tv.backgroundColor = .textBackgroundColor
        editor.restyleAll()
    }

    private func setUpSplit() {
        let scroll = OutlineScrollView()
        scroll.hasVerticalScroller = true
        scroll.documentView = textView
        scroll.drawsBackground = true
        let content = NSViewController()
        content.view = scroll
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 160
        sidebarItem.maximumThickness = 360
        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(NSSplitViewItem(viewController: content))
        split.splitView.autosaveName = "PlainFocusTaskSplit"
        sidebar.onSelect = { [weak self] item in self?.select(item) }
        sidebar.editorView = textView
        sidebar.onDoubleClick = { [weak self] item in
            guard let self, item.kind == .project, let id = item.lineID, let line = self.editor.line(withID: id) else { return }
            self.editor.hoist(line: line)
        }
        sidebar.menuItems = { [weak self] item in self?.sidebarMenu(for: item) ?? [] }
        sidebar.onMoveProject = { [weak self] id, parent, index in self?.moveProject(id, parent: parent, index: index) ?? false }
        sidebar.onDropSelection = { [weak self] target in
            guard let self else { return false }
            if target.kind == .home { self.editor.perform { $0.moveToProject(nil) }; return true }
            guard let id = target.lineID, let line = self.editor.line(withID: id) else { return false }
            self.editor.perform { $0.moveToProject(line) }
            return true
        }
        window?.contentViewController = split
        window?.setContentSize(NSSize(width: 960, height: 680))
        window?.makeFirstResponder(textView)
    }

    private func setUpToolbar() {
        let toolbar = NSToolbar(identifier: "PlainFocusTaskToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window?.toolbar = toolbar
        window?.toolbarStyle = .unified
    }

    override func windowTitle(forDocumentDisplayName displayName: String) -> String { displayName }

    /// 사이드바·검색 필드에 포커스가 있어도 편집기 메뉴 명령이 동작하게 한다.
    override func supplementalTarget(forAction action: Selector, sender: Any?) -> Any? {
        if textView.responds(to: action), !(window?.firstResponder is NSTextView && window?.firstResponder !== textView && Self.textActions.contains(action)) {
            return textView
        }
        return super.supplementalTarget(forAction: action, sender: sender)
    }

    /// 검색 필드 편집기가 직접 처리해야 하는 일반 텍스트 명령
    private static let textActions: Set<Selector> = [
        #selector(NSText.copy(_:)), #selector(NSText.paste(_:)), #selector(NSText.cut(_:)), #selector(NSText.selectAll(_:)),
        #selector(NSText.delete(_:)), #selector(UndoManager.undo), #selector(UndoManager.redo),
    ]

    // MARK: 툴바

    private static let searchID = NSToolbarItem.Identifier("search")
    private static let pomodoroID = NSToolbarItem.Identifier("pomodoro")

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        var ids: [NSToolbarItem.Identifier] = [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace]
        if PomodoroController.shared.settings.showToolbar { ids.append(Self.pomodoroID) }
        return ids + [Self.searchID]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, Self.pomodoroID, Self.searchID]
    }

    /// 설정에서 툴바 표시를 바꾸면 열린 창에 바로 넣거나 뺀다.
    @objc private func pomodoroPresentationChanged() {
        guard let toolbar = window?.toolbar else { return }
        let index = toolbar.items.firstIndex { $0.itemIdentifier == Self.pomodoroID }
        let wanted = PomodoroController.shared.settings.showToolbar
        if wanted, index == nil {
            let at = toolbar.items.firstIndex { $0.itemIdentifier == Self.searchID } ?? toolbar.items.count
            toolbar.insertItem(withItemIdentifier: Self.pomodoroID, at: at)
        } else if !wanted, let index {
            toolbar.removeItem(at: index)
        }
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if id == Self.pomodoroID {
            let item = NSToolbarItem(itemIdentifier: id)
            item.label = "뽀모도로"
            item.view = NSHostingView(rootView: PomodoroToolbarButton())
            return item
        }
        guard id == Self.searchID else { return nil }
        let item = NSSearchToolbarItem(itemIdentifier: id)
        item.searchField.placeholderString = "검색 (예: @today, project Work//not @done)"
        item.searchField.delegate = self
        item.searchField.sendsSearchStringImmediately = true
        item.preferredWidthForSearchField = 300
        searchField = item.searchField
        return item
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField, field === searchField else { return }
        let error = editor.setFilter(field.stringValue)
        field.textColor = error == nil ? .labelColor : .systemRed
        field.toolTip = error
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if control === searchField, selector == #selector(NSResponder.insertNewline(_:)) || selector == #selector(NSResponder.cancelOperation(_:)) {
            if selector == #selector(NSResponder.cancelOperation(_:)) { closeSearch(nil) }
            window?.makeFirstResponder(self.textView)
            return true
        }
        return false
    }

    // MARK: 사이드바

    private func scheduleSidebarReload() {
        sidebarTimer?.invalidate()
        sidebarTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadSidebar() }
        }
    }

    func reloadSidebar() {
        let s = SidebarModel.build(editor)
        sections = s
        var roots = [s.home, s.projects, s.searches, s.tags]
        roots.removeAll { $0.kind == .group && $0.children.isEmpty }
        sidebar.reload(roots, selectedKey: currentKey)
    }

    private var currentKey: String? {
        if !editor.filterQuery.isEmpty {
            let all = sections.map { [$0.searches, $0.tags].flatMap { $0.flattened() }.map(\.0) } ?? []
            return all.first { $0.query == editor.filterQuery }?.key
        }
        if let f = editor.focusedLine { return "p-\(editor.index[f].id)" }
        return editor.hoistedLine == nil ? "home" : nil
    }

    private func syncState() {
        window?.subtitle = editor.focusPath
        if let field = searchField, field.stringValue != editor.filterQuery, window?.firstResponder !== field.currentEditor() {
            field.stringValue = editor.filterQuery
            field.textColor = .labelColor
        }
        sidebar.select(key: currentKey)
    }

    func select(_ item: SidebarItem) {
        switch item.kind {
        case .home: editor.goHome()
        case .project:
            if let id = item.lineID, let line = editor.line(withID: id) {
                if !editor.filterQuery.isEmpty { editor.setFilter("") }
                editor.focus(line: line)
            }
        case .search, .tag, .tagValue:
            if editor.focusedLine != nil || editor.hoistedLine != nil { editor.focus(line: nil) }
            applyFilter(item.query ?? "")
        case .group: break
        }
        // 마우스로 고르면 편집기로 바로 입력하게 하고, 화살표로 고르면 사이드바에 포커스를 둔다
        if let type = NSApp.currentEvent?.type, type == .leftMouseDown || type == .leftMouseUp {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.window?.makeFirstResponder(self.textView)
            }
        }
    }

    func applyFilter(_ query: String) {
        searchField?.stringValue = query
        searchField?.textColor = .labelColor
        editor.setFilter(query)
    }

    private func sidebarMenu(for item: SidebarItem?) -> [NSMenuItem] {
        func entry(_ title: String, _ action: @escaping () -> Void) -> NSMenuItem {
            let m = NSMenuItem(title: title, action: #selector(runMenuClosure(_:)), keyEquivalent: "")
            m.target = self
            m.representedObject = action
            return m
        }
        switch item?.kind {
        case .project?:
            guard let item, let id = item.lineID else { return [] }
            return [
                entry("포커스") { [weak self] in self?.select(item) },
                entry("호이스트") { [weak self] in
                    guard let self, let line = self.editor.line(withID: id) else { return }
                    self.editor.hoist(line: line)
                },
            ]
        case .search?:
            guard let item else { return [] }
            return [
                entry("새 검색…") { [weak self] in self?.newSidebarSearch(nil) },
                entry("검색 편집…") { [weak self] in self?.editSearch(item) },
                entry("검색 삭제") { [weak self] in self?.deleteSearch(item) },
            ]
        default:
            return [entry("새 검색…") { [weak self] in self?.newSidebarSearch(nil) }]
        }
    }

    @objc private func runMenuClosure(_ sender: NSMenuItem) { (sender.representedObject as? () -> Void)?() }

    /// 사이드바에서 끌어놓은 프로젝트를 새 부모의 `index`번째 자리로 옮긴다.
    private func moveProject(_ id: Int, parent: SidebarItem?, index childIndex: Int) -> Bool {
        let idx = editor.index
        guard let source = editor.line(withID: id) else { return false }
        let p = parent.flatMap { $0.lineID }.flatMap { editor.line(withID: $0) } ?? -1
        let projects = idx.children(p).filter { idx[$0].type == .project }
        let before: Int
        if childIndex < 0 { before = p + 1 } else if childIndex < projects.count { before = projects[childIndex] } else { before = idx.branchEnd(p) }
        let level = p >= 0 ? idx[p].level + 1 : 0
        guard var edit = editor.snapshot().moveBranch(source, before: before, level: level) else { return false }
        if p >= 0 { edit.expandIDs = [idx[p].id] }
        editor.apply(edit)
        reloadSidebar()
        return true
    }

    // MARK: 검색 명령

    @objc func beginSearch(_ sender: Any?) {
        if let field = searchField { window?.makeFirstResponder(field) }
    }

    @objc func refreshSearch(_ sender: Any?) { editor.refreshFilter() }

    @objc func closeSearch(_ sender: Any?) {
        searchField?.stringValue = ""
        editor.setFilter("")
        window?.makeFirstResponder(textView)
    }

    @objc func newSidebarSearch(_ sender: Any?) {
        askSearch(name: "", query: editor.filterQuery, global: false) { [weak self] name, query, global in
            guard let self else { return }
            if global {
                GlobalConfig.shared.updateSearch(old: nil, new: .init(name: name, query: query))
            } else {
                self.saveDocumentSearch(replacing: nil, name: name, query: query)
            }
            self.reloadSidebar()
        }
    }

    /// 문서 안 `Searches:` 프로젝트에 검색을 넣거나 바꾼다.
    private func saveDocumentSearch(replacing line: Int?, name: String, query: String) {
        let index = editor.index, text = editor.text
        var new = (0..<index.count).map { NewLine(text: text.substring(with: index[$0].range), source: $0) }
        let body = "\(name) @search(\(LineIndex.escapeTagValue(query)))"
        if let line {
            new[line].text = index.indentString(line, text) + body
        } else if let p = (0..<index.count).first(where: { index[$0].type == .project && index.displayName($0, text).lowercased() == "searches" }) {
            new.insert(NewLine(text: index.indentString(p, text) + "\t" + body, source: nil), at: index[p].branchEnd)
        } else {
            var end = new.count
            while end > 0, new[end - 1].text.isEmpty { end -= 1 }
            new.insert(contentsOf: [NewLine(text: "Searches:", source: nil), NewLine(text: "\t" + body, source: nil)], at: end)
        }
        let snap = editor.snapshot()
        if let edit = snap.makeEdit(new, select: snap.selectionSpec.start) { editor.apply(edit, keepSelection: true) }
    }

    private func documentSearchLine(_ query: String) -> Int? {
        (0..<editor.index.count).first { editor.index[$0].tag("search")?.value == query }
    }

    private var selectedSearch: SidebarItem? {
        guard let item = sidebar.selectedItem, item.kind == .search else { return nil }
        return item
    }

    @objc func editSidebarSearch(_ sender: Any?) {
        guard let item = selectedSearch else { NSSound.beep(); return }
        editSearch(item)
    }

    @objc func deleteSidebarSearch(_ sender: Any?) {
        guard let item = selectedSearch else { NSSound.beep(); return }
        deleteSearch(item)
    }

    private func editSearch(_ item: SidebarItem) {
        guard let old = item.query else { return }
        askSearch(name: item.title, query: old, global: item.global) { [weak self] name, query, global in
            guard let self else { return }
            // 저장 위치가 바뀌면 옛 자리에서 지우고 새 자리에 넣는다
            if item.global { GlobalConfig.shared.updateSearch(old: old, new: global ? .init(name: name, query: query) : nil) }
            else if let line = self.documentSearchLine(old) {
                if global {
                    let snap = self.editor.snapshot(selection: NSRange(location: self.editor.index[line].bodyStart, length: 0))
                    if let edit = snap.deleteLines() { self.editor.apply(edit, keepSelection: true) }
                } else {
                    self.saveDocumentSearch(replacing: line, name: name, query: query)
                }
            }
            if global && !item.global { GlobalConfig.shared.updateSearch(old: nil, new: .init(name: name, query: query)) }
            if !global && item.global { self.saveDocumentSearch(replacing: nil, name: name, query: query) }
            self.applyFilter(query)
            self.reloadSidebar()
        }
    }

    private func deleteSearch(_ item: SidebarItem) {
        guard let query = item.query else { return }
        if item.global {
            GlobalConfig.shared.updateSearch(old: query, new: nil)
        } else if let line = documentSearchLine(query) {
            let snap = editor.snapshot(selection: NSRange(location: editor.index[line].bodyStart, length: 0))
            if let edit = snap.deleteLines() { editor.apply(edit, keepSelection: true) }
        }
        if editor.filterQuery == query { closeSearch(nil) }
        reloadSidebar()
    }

    private func askSearch(name: String, query: String, global: Bool, completion: @escaping (String, String, Bool) -> Void) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "사이드바 검색"
        alert.informativeText = "이름과 질의를 적으세요. 괄호도 그대로 쓰면 됩니다."
        let nameField = NSTextField(string: name)
        nameField.placeholderString = "이름"
        let queryField = NSTextField(string: query)
        queryField.placeholderString = "질의 (예: @due <[d] next week and not @done)"
        let shared = NSButton(checkboxWithTitle: "모든 문서에 표시 (공유 searches 파일에 저장)", target: nil, action: nil)
        shared.state = global ? .on : .off
        let stack = NSStackView(views: [nameField, queryField, shared])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.frame = NSRect(x: 0, y: 0, width: 340, height: 84)
        nameField.widthAnchor.constraint(equalToConstant: 340).isActive = true
        queryField.widthAnchor.constraint(equalToConstant: 340).isActive = true
        alert.accessoryView = stack
        alert.addButton(withTitle: "저장")
        alert.addButton(withTitle: "취소")
        alert.window.initialFirstResponder = nameField
        alert.beginSheetModal(for: window) { response in
            let n = nameField.stringValue.trimmingCharacters(in: .whitespaces)
            let q = queryField.stringValue.trimmingCharacters(in: .whitespaces)
            guard response == .alertFirstButtonReturn, !n.isEmpty, !q.isEmpty else { return }
            if let error = ItemPath(q).error {
                let a = NSAlert()
                a.messageText = "잘못된 질의"
                a.informativeText = error
                a.runModal()
                return
            }
            completion(n, q, shared.state == .on)
        }
    }

    @objc func showSidebarAndExpandCompletely(_ sender: Any?) {
        if let item = split.splitViewItems.first, item.isCollapsed { split.toggleSidebar(sender) }
        sidebar.expandAll()
    }

    @objc func toggleFloating(_ sender: Any?) {
        guard let window else { return }
        window.level = window.level == .floating ? .normal : .floating
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleFloating(_:)): item.state = window?.level == .floating ? .on : .off
        case #selector(editSidebarSearch(_:)), #selector(deleteSidebarSearch(_:)): return selectedSearch != nil
        case #selector(closeSearch(_:)), #selector(refreshSearch(_:)): return !editor.filterQuery.isEmpty
        default: break
        }
        return true
    }

    // MARK: 팔레트

    private func choice(for item: SidebarItem, depth: Int) -> PaletteChoice {
        PaletteChoice(title: item.title, detail: item.query ?? "", depth: depth, symbol: item.symbol) { [weak self] in self?.select(item) }
    }

    /// 줄 id가 바뀌었을 수 있으니 팔레트를 열 때마다 사이드바 모델을 새로 만든다.
    private func freshSections() -> (home: SidebarItem, projects: SidebarItem, searches: SidebarItem, tags: SidebarItem)? {
        reloadSidebar()
        return sections
    }

    private func choices(_ groups: [SidebarItem], includeHome: Bool) -> [PaletteChoice] {
        var result: [PaletteChoice] = []
        if includeHome, let s = sections { result.append(choice(for: s.home, depth: 0)) }
        for g in groups { result += g.children.flatMap { $0.flattened() }.map { choice(for: $0.0, depth: $0.1) } }
        return result
    }

    @objc func showGoToPalette(_ sender: Any?) {
        guard let s = freshSections(), let window else { return }
        ChoicePalette.show(over: window, placeholder: "무엇이든 이동", choices: choices([s.projects, s.searches, s.tags], includeHome: true))
    }

    @objc func showProjectsPalette(_ sender: Any?) {
        guard let s = freshSections(), let window else { return }
        ChoicePalette.show(over: window, placeholder: "프로젝트로 이동", choices: choices([s.projects], includeHome: true))
    }

    @objc func showSearchesPalette(_ sender: Any?) {
        guard let s = freshSections(), let window else { return }
        ChoicePalette.show(over: window, placeholder: "검색으로 이동", choices: choices([s.searches], includeHome: false))
    }

    @objc func showTagsPalette(_ sender: Any?) {
        guard let s = freshSections(), let window else { return }
        ChoicePalette.show(over: window, placeholder: "태그로 이동", choices: choices([s.tags], includeHome: false))
    }

    @objc func showCommandsPalette(_ sender: Any?) {
        guard let window, let menu = NSApp.mainMenu else { return }
        var result: [PaletteChoice] = []
        func walk(_ menu: NSMenu, _ path: String) {
            for item in menu.items where !item.isSeparatorItem && !item.isHidden {
                if let sub = item.submenu {
                    walk(sub, path.isEmpty ? item.title : path + " ▸ " + item.title)
                } else if let action = item.action, action != #selector(showCommandsPalette(_:)) {
                    let target = item.target
                    result.append(PaletteChoice(title: item.title, detail: path + "  " + Self.shortcut(item)) {
                        NSApp.sendAction(action, to: target, from: item)
                    })
                }
            }
        }
        for top in menu.items { if let sub = top.submenu { walk(sub, top.title) } }
        ChoicePalette.show(over: window, placeholder: "명령", choices: result)
    }

    private static func shortcut(_ item: NSMenuItem) -> String {
        guard !item.keyEquivalent.isEmpty else { return "" }
        let m = item.keyEquivalentModifierMask
        var s = ""
        if m.contains(.control) { s += "⌃" }
        if m.contains(.option) { s += "⌥" }
        if m.contains(.shift) || item.keyEquivalent != item.keyEquivalent.lowercased() { s += "⇧" }
        if m.contains(.command) { s += "⌘" }
        let arrows: [Int: String] = [NSUpArrowFunctionKey: "↑", NSDownArrowFunctionKey: "↓", NSLeftArrowFunctionKey: "←", NSRightArrowFunctionKey: "→"]
        let scalar = Int(item.keyEquivalent.unicodeScalars.first!.value)
        return s + (arrows[scalar] ?? item.keyEquivalent.uppercased())
    }

    func showMoveToProject() {
        guard let window else { return }
        guard let s = freshSections() else { return }
        var list = [PaletteChoice(title: "홈", symbol: "house") { [weak self] in self?.editor.perform { $0.moveToProject(nil) } }]
        for (item, depth) in s.projects.children.flatMap({ $0.flattened() }) {
            list.append(PaletteChoice(title: item.title, depth: depth, symbol: "folder") { [weak self] in
                guard let self, let id = item.lineID, let line = self.editor.line(withID: id) else { return }
                self.editor.perform { $0.moveToProject(line) }
            })
        }
        ChoicePalette.show(over: window, placeholder: "프로젝트로 옮기기 (없는 이름이면 새로 만듦)", choices: list) { [weak self] name in
            self?.editor.perform { $0.moveToProject(nil, newProject: name) }
        }
    }

    func showTagWith() {
        guard let window else { return }
        let names = freshSections()?.tags.children.map { String($0.title.dropFirst()) } ?? []
        let dateTags = ["due": "마감일", "start": "시작일"]
        let all = Array(Set(names).union(["due", "start", "today", "done"])).sorted()
        let list = all.map { name in
            PaletteChoice(title: "@" + name, symbol: "tag") { [weak self] in
                guard let self else { return }
                if let title = dateTags[name] { self.textView.toggleDateTag(name, title: title) }
                else if name == "done" { self.editor.toggleDone() }
                else { self.editor.perform { $0.toggleTag(name) } }
            }
        }
        ChoicePalette.show(over: window, placeholder: "태그 붙이기 (⇧↑↓로 여러 개, 새 태그는 입력 후 ↩)", choices: list, multiple: true) { [weak self] input in
            self?.applyTags(input)
        }
    }

    /// `@a @b(1) c` 형태의 입력을 태그 목록으로 바꿔 붙이거나(모두 있으면) 뗀다.
    private func applyTags(_ input: String) {
        let normalized = input.split(separator: " ").map { $0.hasPrefix("@") ? String($0) : "@" + $0 }.joined(separator: " ")
        let tags = LineText.tags(normalized)
        guard !tags.isEmpty else { return }
        let snap = editor.snapshot()
        let removeAll = tags.allSatisfy { snap.hasTag($0.name) }
        let lines = snap.visibleSelected.filter { !editor.index[$0].isBlank }
        var new = snap.allLines()
        for i in lines {
            for tag in tags {
                new[i].text = removeAll ? LineText.removeTag(new[i].text, tag.name) : LineText.setTag(new[i].text, tag.name, tag.value)
            }
        }
        if let edit = snap.editKeepingSelection(new) { editor.apply(edit) }
    }

    func askDate(title: String, completion: @escaping (String?) -> Void) {
        guard let window else { return }
        DatePrompt.ask(over: window, title: title, completion: completion)
    }

    // MARK: 미리 알림

    @objc func importReminders(_ sender: Any?) { importReminders(move: true) }
    @objc func importReminderCopies(_ sender: Any?) { importReminders(move: false) }
    @objc func exportToReminders(_ sender: Any?) { exportReminders(move: true) }
    @objc func exportCopyToReminders(_ sender: Any?) { exportReminders(move: false) }

    private func remindersDenied() {
        let a = NSAlert()
        a.messageText = "미리 알림에 접근할 수 없습니다"
        a.informativeText = "시스템 설정 > 개인정보 보호 및 보안 > 미리 알림에서 PlainFocusTask를 허용하세요."
        if let window { a.beginSheetModal(for: window) }
    }

    /// 미리 알림을 골라 현재 항목 아래에 작업으로 넣는다. `move`면 미리 알림에서 지운다.
    private func importReminders(move: Bool) {
        Task { @MainActor in
            guard await Reminders.requestAccess() else { return remindersDenied() }
            let items = await Reminders.incomplete()
            guard let window, !items.isEmpty else { NSSound.beep(); return }
            var chosen: [Reminders.Item] = []
            let choices = items.map { item in
                PaletteChoice(title: item.title, detail: item.list, symbol: "checklist") { chosen.append(item) }
            }
            ChoicePalette.show(over: window, placeholder: move ? "가져올 미리 알림 (⇧↑↓로 여러 개)" : "사본으로 가져올 미리 알림", choices: choices, multiple: true, completion: { [weak self] in
                guard let self, !chosen.isEmpty else { return }
                self.editor.perform { snap in snap.insertLines { indent in chosen.flatMap { Reminders.lines(for: $0, indent: indent) } } }
                if move { Reminders.remove(ids: chosen.map(\.id)) }
            })
        }
    }

    /// 선택한 항목을 미리 알림 목록에 만든다. `move`면 문서에서 지운다.
    private func exportReminders(move: Bool) {
        let snap = editor.snapshot()
        let index = editor.index, text = editor.text
        let tops = index.commonAncestors(snap.visibleSelected.filter { !index[$0].isBlank })
        guard !tops.isEmpty else { NSSound.beep(); return }
        let items = tops.map { t in
            (title: index.displayName(t, text),
             notes: ((t + 1)..<index[t].branchEnd).map { index.body($0, text) }.joined(separator: "\n"),
             due: index[t].tag("due")?.value.flatMap { DateParser.parse($0) })
        }
        Task { @MainActor in
            guard await Reminders.requestAccess() else { return remindersDenied() }
            guard let window else { return }
            let choices = Reminders.lists.map { list in
                PaletteChoice(title: list.title, symbol: "list.bullet") { [weak self] in
                    guard let self else { return }
                    do {
                        try Reminders.export(items, toList: list.id)
                        if move, let edit = self.editor.snapshot().removeBranches(tops) { self.editor.apply(edit) }
                    } catch {
                        NSAlert(error: error).beginSheetModal(for: window)
                    }
                }
            }
            ChoicePalette.show(over: window, placeholder: "내보낼 미리 알림 목록", choices: choices)
        }
    }

    @objc override func newWindowForTab(_ sender: Any?) {
        guard let window, let doc = try? NSDocumentController.shared.openUntitledDocumentAndDisplay(false) else { return }
        doc.makeWindowControllers()
        if let newWindow = doc.windowControllers.first?.window {
            window.addTabbedWindow(newWindow, ordered: .above)
            newWindow.makeKeyAndOrderFront(nil)
        }
    }
}
