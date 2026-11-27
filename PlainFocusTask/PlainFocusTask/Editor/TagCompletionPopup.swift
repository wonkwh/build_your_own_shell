import AppKit

/// `@`를 입력하면 커서 아래에 뜨는 태그 자동 완성 목록. 키 입력은 편집기가 계속 받는다.
final class TagCompletionPopup: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 160),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    private let table = NSTableView()
    private(set) var items: [String] = []
    /// 바꿀 범위(`@` 다음부터 커서까지)
    private(set) var range = NSRange(location: 0, length: 0)
    var onAccept: ((String, NSRange) -> Void)?

    var isVisible: Bool { panel.isVisible }

    override init() {
        super.init()
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .popUpMenu
        let effect = NSVisualEffectView()
        effect.material = .menu
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 8
        effect.layer?.masksToBounds = true
        let column = NSTableColumn(identifier: .init("tag"))
        table.addTableColumn(column)
        table.headerView = nil
        table.backgroundColor = .clear
        table.rowHeight = 20
        table.style = .plain
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clicked)
        table.refusesFirstResponder = true
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: effect.topAnchor, constant: 4),
            scroll.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -4),
            scroll.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 4),
            scroll.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -4),
        ])
        panel.contentView = effect
    }

    /// - Parameter caret: 화면 좌표의 커서 사각형
    func show(_ items: [String], range: NSRange, below caret: NSRect, in parent: NSWindow) {
        self.items = items
        self.range = range
        table.reloadData()
        table.selectRowIndexes([0], byExtendingSelection: false)
        table.scrollRowToVisible(0)
        let height = min(CGFloat(items.count) * (table.rowHeight + table.intercellSpacing.height) + 10, 200)
        panel.setFrame(NSRect(x: caret.minX - 8, y: caret.minY - height - 2, width: 220, height: height), display: true)
        if panel.parent == nil { parent.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil)
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    func move(_ d: Int) {
        guard !items.isEmpty else { return }
        let row = min(max(table.selectedRow + d, 0), items.count - 1)
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    func accept() {
        guard table.selectedRow >= 0, table.selectedRow < items.count else { return }
        let name = items[table.selectedRow]
        hide()
        onAccept?(name, range)
    }

    @objc private func clicked() { accept() }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let field = NSTextField(labelWithString: "@" + items[row])
        field.lineBreakMode = .byTruncatingTail
        return field
    }
}
