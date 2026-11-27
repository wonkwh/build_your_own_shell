import Foundation

/// 모든 문서가 함께 쓰는 사이드바 검색(searches.taskpaper)과 태그 목록(tags.taskpaper).
final class GlobalConfig {
    static let shared = GlobalConfig()

    struct Search { var name: String; var query: String }
    struct Tags { var include: [String] = []; var exclude: Set<String> = [] }

    let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("PlainFocusTask", isDirectory: true)
    }()

    var searchesURL: URL { directory.appendingPathComponent("searches.taskpaper") }
    var tagsURL: URL { directory.appendingPathComponent("tags.taskpaper") }

    private var cache: [URL: (Date, String)] = [:]

    /// 없으면 TaskPaper 기본값으로 만든다.
    func ensureFiles() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let defaults: [(URL, String)] = [
            (searchesURL, "모든 문서의 사이드바에 보일 검색을 적어 두는 설정 개요입니다.\n\nSearches:\n\tToday @search(@today union @due <[d] tomorrow)\n\tNot Done @search(not @done except @done//*)\n"),
            (tagsURL, "모든 문서의 사이드바에 보이거나(Include) 빠질(Exclude) 태그를 적어 두는 설정 개요입니다.\n\nInclude Tags: @due @start @today @done\nExclude Tags: @search\n"),
        ]
        for (url, text) in defaults where !FileManager.default.fileExists(atPath: url.path) {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func read(_ url: URL) -> String {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        if let (date, text) = cache[url], date == modified { return text }
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        cache[url] = (modified, text)
        return text
    }

    var searches: [Search] {
        let text = read(searchesURL) as NSString
        let index = LineIndex(text)
        return (0..<index.count).compactMap { i in
            guard let q = index[i].tag("search")?.value, !q.isEmpty else { return nil }
            return Search(name: index.displayName(i, text), query: q)
        }
    }

    /// 공유 searches 파일의 검색을 추가·바꾸기·지우기. `old`가 없으면 추가, `new`가 없으면 지운다.
    func updateSearch(old: String?, new: Search?) {
        var lines = read(searchesURL).components(separatedBy: "\n")
        let line = new.map { "\t\($0.name) @search(\(LineIndex.escapeTagValue($0.query)))" }
        if let old, let k = lines.firstIndex(where: { LineText.tags($0).first { $0.name == "search" }?.value == old }) {
            if let line { lines[k] = line } else { lines.remove(at: k) }
        } else if let line {
            if let k = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).lowercased() == "searches:" }) {
                var end = k + 1
                while end < lines.count, lines[end].hasPrefix("\t") || lines[end].hasPrefix(" ") { end += 1 }
                lines.insert(line, at: end)
            } else {
                lines += ["Searches:", line]
            }
        }
        try? lines.joined(separator: "\n").write(to: searchesURL, atomically: true, encoding: .utf8)
        cache[searchesURL] = nil
    }

    var tags: Tags {
        var result = Tags()
        for line in read(tagsURL).components(separatedBy: .newlines) {
            let names = LineText.tags(line).map(\.name)
            if line.lowercased().hasPrefix("include tags:") { result.include += names }
            if line.lowercased().hasPrefix("exclude tags:") { result.exclude.formUnion(names) }
        }
        return result
    }
}
