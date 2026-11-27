import AppKit

/// 사이드바 한 줄.
final class SidebarItem: NSObject {
    enum Kind { case group, home, project, search, tag, tagValue }

    let kind: Kind
    let title: String
    /// 다시 불러온 뒤 선택·펼침을 되살리는 키
    let key: String
    /// 검색·태그면 필터 질의
    let query: String?
    /// 프로젝트면 줄 id
    let lineID: Int?
    var children: [SidebarItem] = []

    init(_ kind: Kind, _ title: String, key: String, query: String? = nil, lineID: Int? = nil) {
        self.kind = kind
        self.title = title
        self.key = key
        self.query = query
        self.lineID = lineID
    }

    var symbol: String {
        switch kind {
        case .group: ""
        case .home: "house"
        case .project: "folder"
        case .search: "magnifyingglass"
        case .tag: "tag"
        case .tagValue: "number"
        }
    }

    /// 자신과 모든 자손을 깊이와 함께 펼친다. 팔레트 목록에 쓴다.
    func flattened(depth: Int = 0) -> [(SidebarItem, Int)] {
        [(self, depth)] + children.flatMap { $0.flattened(depth: depth + 1) }
    }
}

/// 문서와 전역 설정에서 사이드바 목록을 만든다.
enum SidebarModel {
    static func build(_ editor: OutlineEditor) -> (home: SidebarItem, projects: SidebarItem, searches: SidebarItem, tags: SidebarItem) {
        let index = editor.index, text = editor.text
        let home = SidebarItem(.home, "홈", key: "home")
        let projects = SidebarItem(.group, "프로젝트", key: "g-projects")
        func gather(_ parent: Int, into item: SidebarItem) {
            for c in index.children(parent) where index[c].type == .project {
                let p = SidebarItem(.project, index.displayName(c, text), key: "p-\(index[c].id)", lineID: index[c].id)
                gather(c, into: p)
                item.children.append(p)
            }
        }
        gather(-1, into: projects)

        let searches = SidebarItem(.group, "검색", key: "g-searches")
        for i in 0..<index.count {
            guard let q = index[i].tag("search")?.value, !q.isEmpty else { continue }
            searches.children.append(SidebarItem(.search, index.displayName(i, text), key: "s-\(q)", query: q))
        }
        for s in GlobalConfig.shared.searches {
            searches.children.append(SidebarItem(.search, s.name, key: "s-\(s.query)", query: s.query))
        }

        let tags = SidebarItem(.group, "태그", key: "g-tags")
        let config = GlobalConfig.shared.tags
        var values: [String: Set<String>] = [:]
        for name in config.include { values[name, default: []] = [] }
        for line in index.lines {
            for tag in line.tags where !config.exclude.contains(tag.name) {
                values[tag.name, default: []].formUnion(tag.value.map { $0.isEmpty ? [] : [$0] } ?? [])
            }
        }
        for name in values.keys.sorted() {
            let t = SidebarItem(.tag, "@" + name, key: "t-\(name)", query: "@" + name)
            for v in values[name]!.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
                let q = "@\(name) contains[l] \"\(v.replacingOccurrences(of: "\"", with: "\\\""))\""
                t.children.append(SidebarItem(.tagValue, v, key: "v-\(name)-\(v)", query: q))
            }
            tags.children.append(t)
        }
        return (home, projects, searches, tags)
    }
}

/// 사이드바 목록 보기.
final class SidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    let outlineView = NSOutlineView()
    private(set) var roots: [SidebarItem] = []
    var onSelect: ((SidebarItem) -> Void)?
    private var suppress = false
    private var collapsedKeys = Set<String>()

    override func loadView() {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let column = NSTableColumn(identifier: .init("main"))
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.style = .sourceList
        outlineView.floatsGroupRows = false
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.autosaveExpandedItems = false
        scroll.documentView = outlineView
        view = scroll
    }

    func reload(_ items: [SidebarItem], selectedKey: String?) {
        suppress = true
        roots = items
        outlineView.reloadData()
        func expand(_ item: SidebarItem) {
            guard !item.children.isEmpty else { return }
            if !collapsedKeys.contains(item.key), item.kind == .group || item.kind == .project { outlineView.expandItem(item) }
            item.children.forEach(expand)
        }
        roots.forEach(expand)
        select(key: selectedKey)
        suppress = false
    }

    func select(key: String?) {
        suppress = true
        defer { suppress = false }
        guard let key else { outlineView.deselectAll(nil); return }
        for row in 0..<outlineView.numberOfRows {
            if let item = outlineView.item(atRow: row) as? SidebarItem, item.key == key {
                outlineView.selectRowIndexes([row], byExtendingSelection: false)
                return
            }
        }
        outlineView.deselectAll(nil)
    }

    func expandAll() {
        collapsedKeys = []
        outlineView.expandItem(nil, expandChildren: true)
    }

    var selectedItem: SidebarItem? { outlineView.item(atRow: outlineView.selectedRow) as? SidebarItem }

    // MARK: 데이터

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? SidebarItem)?.children.count ?? roots.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? SidebarItem)?.children[index] ?? roots[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !((item as? SidebarItem)?.children.isEmpty ?? true)
    }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        (item as? SidebarItem)?.kind == .group
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        (item as? SidebarItem)?.kind != .group
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let item = item as? SidebarItem else { return nil }
        let id = NSUserInterfaceItemIdentifier(item.kind == .group ? "group" : "cell")
        let cell = outlineView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? makeCell(id, group: item.kind == .group)
        cell.textField?.stringValue = item.title
        cell.imageView?.image = item.symbol.isEmpty ? nil : NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil)
        return cell
    }

    private func makeCell(_ id: NSUserInterfaceItemIdentifier, group: Bool) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = id
        let field = NSTextField(labelWithString: "")
        field.lineBreakMode = .byTruncatingTail
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        cell.textField = field
        if group {
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                field.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
                field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        } else {
            let image = NSImageView()
            image.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(image)
            cell.imageView = image
            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 16),
                field.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
                field.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
                field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !suppress, let item = selectedItem else { return }
        onSelect?(item)
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        if let item = notification.userInfo?["NSObject"] as? SidebarItem { collapsedKeys.insert(item.key) }
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        if let item = notification.userInfo?["NSObject"] as? SidebarItem, !suppress { collapsedKeys.remove(item.key) }
    }
}
