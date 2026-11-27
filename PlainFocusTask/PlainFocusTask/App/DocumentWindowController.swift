import AppKit

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
        editor.onTagClicked = { [weak self] tag in self?.applyFilter("@" + tag) }
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
        let scroll = NSScrollView()
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

    // MARK: 툴바

    private static let searchID = NSToolbarItem.Identifier("search")

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, Self.searchID]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
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
        window?.makeFirstResponder(textView)
    }

    func applyFilter(_ query: String) {
        searchField?.stringValue = query
        searchField?.textColor = .labelColor
        editor.setFilter(query)
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
        askSearch(name: "", query: editor.filterQuery) { [weak self] name, query in
            guard let self else { return }
            let text = self.editor.text
            let index = self.editor.index
            var new = (0..<index.count).map { NewLine(text: text.substring(with: index[$0].range), source: $0) }
            let line = "\t\(name) @search(\(LineIndex.escapeTagValue(query)))"
            if let p = (0..<index.count).first(where: { index[$0].type == .project && index.displayName($0, text).lowercased() == "searches" }) {
                new.insert(NewLine(text: line, source: nil), at: index[p].branchEnd)
            } else {
                var end = new.count
                while end > 0, new[end - 1].text.isEmpty { end -= 1 }
                new.insert(contentsOf: [NewLine(text: "Searches:", source: nil), NewLine(text: line, source: nil)], at: end)
            }
            let snap = self.editor.snapshot()
            if let edit = snap.makeEdit(new, select: snap.selectionSpec.start) { self.editor.apply(edit, keepSelection: true) }
            self.reloadSidebar()
        }
    }

    /// 선택한 사이드바 검색이 문서 안 항목이면 그 줄 번호.
    private var selectedEmbeddedSearch: Int? {
        guard let item = sidebar.selectedItem, item.kind == .search, let q = item.query else { return nil }
        return (0..<editor.index.count).first { editor.index[$0].tag("search")?.value == q }
    }

    @objc func editSidebarSearch(_ sender: Any?) {
        guard let i = selectedEmbeddedSearch else { NSSound.beep(); return }
        let index = editor.index, text = editor.text
        askSearch(name: index.displayName(i, text), query: index[i].tag("search")?.value ?? "") { [weak self] name, query in
            guard let self else { return }
            var new = (0..<index.count).map { NewLine(text: text.substring(with: index[$0].range), source: $0) }
            new[i].text = index.indentString(i, text) + name + " @search(\(LineIndex.escapeTagValue(query)))"
            let snap = self.editor.snapshot()
            if let edit = snap.makeEdit(new, select: snap.selectionSpec.start) { self.editor.apply(edit, keepSelection: true) }
            self.applyFilter(query)
            self.reloadSidebar()
        }
    }

    @objc func deleteSidebarSearch(_ sender: Any?) {
        guard let i = selectedEmbeddedSearch else { NSSound.beep(); return }
        let snap = editor.snapshot(selection: NSRange(location: editor.index[i].bodyStart, length: 0))
        if let edit = snap.deleteLines() { editor.apply(edit, keepSelection: true) }
        closeSearch(nil)
        reloadSidebar()
    }

    private func askSearch(name: String, query: String, completion: @escaping (String, String) -> Void) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "사이드바 검색"
        alert.informativeText = "이름과 질의를 적으세요. 이 문서의 Searches: 프로젝트에 저장됩니다."
        let nameField = NSTextField(string: name)
        nameField.placeholderString = "이름"
        let queryField = NSTextField(string: query)
        queryField.placeholderString = "질의 (예: @due <[d] next week and not @done)"
        let stack = NSStackView(views: [nameField, queryField])
        stack.orientation = .vertical
        stack.frame = NSRect(x: 0, y: 0, width: 320, height: 56)
        nameField.widthAnchor.constraint(equalToConstant: 320).isActive = true
        queryField.widthAnchor.constraint(equalToConstant: 320).isActive = true
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
            completion(n, q)
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
        case #selector(editSidebarSearch(_:)), #selector(deleteSidebarSearch(_:)): return selectedEmbeddedSearch != nil
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
        let list = names.map { name in
            PaletteChoice(title: "@" + name, symbol: "tag") { [weak self] in self?.editor.perform { $0.toggleTag(name) } }
        }
        ChoicePalette.show(over: window, placeholder: "태그 붙이기 (예: @next @priority(1))", choices: list) { [weak self] input in
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

    @objc override func newWindowForTab(_ sender: Any?) {
        guard let window, let doc = try? NSDocumentController.shared.openUntitledDocumentAndDisplay(false) else { return }
        doc.makeWindowControllers()
        if let newWindow = doc.windowControllers.first?.window {
            window.addTabbedWindow(newWindow, ordered: .above)
            newWindow.makeKeyAndOrderFront(nil)
        }
    }
}
