import AppKit

/// 팔레트 선택지.
struct PaletteChoice {
    var title: String
    var detail = ""
    var depth = 0
    var symbol: String?
    var perform: () -> Void
}

/// 무엇이든 이동·명령·프로젝트로 이동·태그 붙이기에 쓰는 퍼지 검색 팔레트.
final class ChoicePalette: NSObject, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private static var current: ChoicePalette?

    private let panel: NSPanel
    private let field = NSTextField()
    private let table = NSTableView()
    private let choices: [PaletteChoice]
    private var shown: [PaletteChoice] = []
    private let custom: ((String) -> Void)?
    private weak var parent: NSWindow?

    /// - Parameter custom: 맞는 선택지가 없을 때 입력한 문자열로 실행한다.
    static func show(over window: NSWindow, placeholder: String, choices: [PaletteChoice], custom: ((String) -> Void)? = nil) {
        current?.close()
        let palette = ChoicePalette(window: window, placeholder: placeholder, choices: choices, custom: custom)
        current = palette
        palette.present()
    }

    private init(window: NSWindow, placeholder: String, choices: [PaletteChoice], custom: ((String) -> Void)?) {
        self.choices = choices
        self.custom = custom
        self.parent = window
        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 320), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.delegate = self

        let effect = NSVisualEffectView()
        effect.material = .menu
        effect.state = .active
        panel.contentView = effect

        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 18)
        field.isBordered = false
        field.focusRingType = .none
        field.drawsBackground = false
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: .init("c"))
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .plain
        table.backgroundColor = .clear
        table.rowHeight = 24
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(choose)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        effect.addSubview(field)
        effect.addSubview(scroll)
        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: effect.topAnchor, constant: 14),
            field.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 14),
            field.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -14),
            scroll.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 6),
            scroll.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -6),
            scroll.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -6),
        ])
        filter()
    }

    private func present() {
        guard let parent else { return }
        let frame = parent.frame
        panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.maxY - panel.frame.height - 80))
        parent.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
    }

    private func close() {
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        if Self.current === self { Self.current = nil }
    }

    /// 순서대로 나오는 글자를 찾고, 붙어 있거나 단어 처음이면 점수를 더 준다.
    static func score(_ query: String, _ title: String) -> Int? {
        guard !query.isEmpty else { return 0 }
        let q = Array(query.lowercased()), t = Array(title.lowercased())
        var qi = 0, score = 0, last = -2
        for (ti, c) in t.enumerated() where qi < q.count && c == q[qi] {
            score += 1
            if ti == last + 1 { score += 3 }
            if ti == 0 || !t[ti - 1].isLetter { score += 2 }
            last = ti
            qi += 1
        }
        return qi == q.count ? score : nil
    }

    private func filter() {
        let q = field.stringValue.trimmingCharacters(in: .whitespaces)
        let scored = choices.enumerated().compactMap { i, c in Self.score(q, c.title).map { (i, $0, c) } }
        shown = q.isEmpty ? choices : scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }.map(\.2)
        table.reloadData()
        if !shown.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }
    }

    @objc private func choose() {
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        let row = table.selectedRow
        let action: (() -> Void)?
        if row >= 0, row < shown.count { action = shown[row].perform }
        else if let custom, !text.isEmpty { action = { custom(text) } }
        else { action = nil }
        let parent = self.parent
        close()
        parent?.makeKeyAndOrderFront(nil)
        action?()
    }

    // MARK: 입력

    func controlTextDidChange(_ obj: Notification) { filter() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveUp(_:)): move(-1)
        case #selector(NSResponder.moveDown(_:)): move(1)
        case #selector(NSResponder.insertNewline(_:)): choose()
        case #selector(NSResponder.cancelOperation(_:)): close(); parent?.makeKeyAndOrderFront(nil)
        default: return false
        }
        return true
    }

    private func move(_ d: Int) {
        guard !shown.isEmpty else { return }
        let row = min(max(table.selectedRow + d, 0), shown.count - 1)
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    func windowDidResignKey(_ notification: Notification) { close() }

    // MARK: 표

    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let c = shown[row]
        let cell = NSTableCellView()
        let title = NSTextField(labelWithString: String(repeating: "    ", count: c.depth) + c.title)
        title.lineBreakMode = .byTruncatingTail
        let detail = NSTextField(labelWithString: c.detail)
        detail.textColor = .secondaryLabelColor
        detail.alignment = .right
        let image = NSImageView(image: c.symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) } ?? NSImage())
        let stack = NSStackView(views: [image, title, detail])
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)
        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 16),
        ])
        return cell
    }
}

/// 제목줄 없는 패널도 키 창이 되게 한다.
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
