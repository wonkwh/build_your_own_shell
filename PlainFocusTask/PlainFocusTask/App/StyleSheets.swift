import AppKit

/// 윈도우 > 스타일시트. 기본 테마와 사용자 폴더의 `.less` 파일을 고른다.
enum StyleSheets {
    static var folder: URL { GlobalConfig.shared.directory.appendingPathComponent("StyleSheets", isDirectory: true) }

    static let builtIn: [(name: String, source: String)] = [
        ("기본", ""),
        ("밝게", """
        @background-color: #ffffff;
        @text-color: #1f1f1f;
        @tint-color: #2f7cf6;
        run[tag] { color: #8c8c8c; }
        item[data-today] { color: #c45500; }
        """),
        ("어둡게", """
        @background-color: #1c1c1e;
        @text-color: #e8e8ea;
        @tint-color: #5aa7ff;
        run[tag] { color: #8e8e93; }
        item[data-today] { color: #ffb340; }
        """),
        ("종이", """
        @background-color: #f6f0e3;
        @text-color: #3b3227;
        @tint-color: #b5651d;
        @font-family: serif;
        item[data-type=project] { color: #7a4f1f; }
        run[tag] { color: mix(#3b3227, #f6f0e3, 45%); }
        item[data-today] { background-color: fade(#e8b04b, 30%); }
        """),
    ]

    static let example = """
    // PlainFocusTask 스타일시트 예시. 이 폴더의 .less 파일은 윈도우 > 스타일시트 메뉴에 나타납니다.
    // 지원: 변수, editor, item[data-type=…], item[data-태그], run[tag], run[tag=data-태그], run[link]
    // 속성: color, background-color, font-weight, font-style, text-decoration, font-size, font-family, line-height-multiple
    @text-color: #222222;
    @background-color: #fdfdfd;
    @tint-color: #0a84ff;
    item[data-type=project] { color: #0a5fbf; }
    item[data-priority] { font-weight: bold; }
    run[tag=data-due] { color: #d23f31; }
    """

    static func ensureFolder() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let sample = folder.appendingPathComponent("예시.less")
        if !FileManager.default.fileExists(atPath: sample.path) { try? example.write(to: sample, atomically: true, encoding: .utf8) }
    }

    static var userSheets: [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "less" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static var names: [String] { builtIn.map(\.name) + userSheets.map { $0.deletingPathExtension().lastPathComponent } }

    static func current(dark: Bool) -> Theme {
        let name = Preferences.styleSheet
        if let b = builtIn.first(where: { $0.name == name }) { return Theme.parse(b.source, name: name, dark: dark) }
        if let url = userSheets.first(where: { $0.deletingPathExtension().lastPathComponent == name }),
           let source = try? String(contentsOf: url, encoding: .utf8) {
            return Theme.parse(source, name: name, dark: dark)
        }
        return Theme()
    }
}

/// 스타일시트 메뉴 항목을 열 때마다 다시 채운다.
final class StyleSheetMenuDelegate: NSObject, NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for name in StyleSheets.names {
            let item = NSMenuItem(title: name, action: #selector(AppDelegate.selectStyleSheet(_:)), keyEquivalent: "")
            item.state = name == Preferences.styleSheet ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "스타일시트 폴더 열기", action: #selector(AppDelegate.openStyleSheetFolder(_:)), keyEquivalent: ""))
    }
}
