import AppKit

/// 스타일시트(.less) 일부를 해석한 테마. 변수, `editor`·`item[...]`·`run[...]` 규칙, 색 함수 mix/lighten/darken/fade를 지원한다.
struct Theme {
    struct Style {
        var color: NSColor?
        var background: NSColor?
        var bold: Bool?
        var italic: Bool?
        var strike: Bool?
        var underline: Bool?
        var size: CGFloat?

        mutating func merge(_ o: Style) {
            color = o.color ?? color
            background = o.background ?? background
            bold = o.bold ?? bold
            italic = o.italic ?? italic
            strike = o.strike ?? strike
            underline = o.underline ?? underline
            size = o.size ?? size
        }
    }

    enum Target: Hashable {
        case editor
        case type(ItemType)
        case itemTag(String)
        case anyTag
        case tag(String)
        case link
    }

    var name = "기본"
    var fontFamily: String?
    var fontSize: CGFloat?
    var lineHeight: CGFloat?
    var background: NSColor?
    var text: NSColor?
    var tint: NSColor?
    var handle: NSColor?
    var rules: [Target: Style] = [:]

    func style(_ t: Target) -> Style? { rules[t] }

    // MARK: 해석

    /// `.less` 일부를 읽는다. 모르는 선택자·속성은 건너뛴다.
    static func parse(_ source: String, name: String, dark: Bool) -> Theme {
        var theme = Theme(name: name)
        var vars: [String: String] = ["appearance": dark ? "dark" : "light"]
        let text = source.replacingOccurrences(of: "//[^\\n]*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "/\\*[\\s\\S]*?\\*/", with: "", options: .regularExpression)
        // 맨 위 변수
        let varRegex = try! NSRegularExpression(pattern: "^\\s*@([\\w-]+)\\s*:\\s*([^;{}]+);", options: .anchorsMatchLines)
        var topLevel = ""
        var depth = 0
        for c in text {
            if c == "{" { depth += 1 } else if c == "}" { depth -= 1 } else if depth == 0 { topLevel.append(c) }
        }
        for m in varRegex.matches(in: topLevel, range: NSRange(topLevel.startIndex..., in: topLevel)) {
            let ns = topLevel as NSString
            vars[ns.substring(with: m.range(at: 1))] = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces)
        }
        func resolve(_ v: String, _ depth: Int = 0) -> String {
            var s = v.trimmingCharacters(in: .whitespaces)
            guard depth < 8 else { return s }
            // @@name: 변수 이름을 담은 변수
            if s.hasPrefix("@@"), let inner = vars[String(s.dropFirst(2))] { s = "@" + resolve(inner, depth + 1).replacingOccurrences(of: "\"", with: "") }
            let r = try! NSRegularExpression(pattern: "@\\{?([\\w-]+)\\}?")
            var out = s
            for m in r.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() {
                let ns = s as NSString
                let key = ns.substring(with: m.range(at: 1))
                if let val = vars[key] { out = (out as NSString).replacingCharacters(in: m.range, with: resolve(val, depth + 1)) }
            }
            return out
        }
        // 규칙 블록
        let blockRegex = try! NSRegularExpression(pattern: "([^{}]+)\\{([^{}]*)\\}")
        let ns = text as NSString
        for m in blockRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let prefix = ns.substring(with: m.range(at: 1)).components(separatedBy: ";").last ?? ""
            let selectors = prefix.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            var props: [String: String] = [:]
            for decl in ns.substring(with: m.range(at: 2)).components(separatedBy: ";") {
                let parts = decl.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                if parts.count == 2 { props[parts[0]] = resolve(parts[1]) }
            }
            for sel in selectors {
                guard let target = Self.target(sel) else { continue }
                if target == .editor {
                    if let f = props["font-family"] { theme.fontFamily = f.replacingOccurrences(of: "\"", with: "") }
                    if let s = props["font-size"], let v = Double(s.filter { "0123456789.".contains($0) }) { theme.fontSize = v }
                    if let l = props["line-height-multiple"], let v = Double(l) { theme.lineHeight = v }
                    if let c = props["background-color"].flatMap(color) { theme.background = c }
                    if let c = props["color"].flatMap(color) { theme.text = c }
                    if let c = props["caret-color"].flatMap(color) { theme.tint = c }
                    continue
                }
                var style = theme.rules[target] ?? Style()
                style.merge(Self.style(props))
                theme.rules[target] = style
            }
        }
        if let c = vars["tint-color"].map({ resolve($0) }).flatMap(color) { theme.tint = theme.tint ?? c }
        if let c = vars["text-color"].map({ resolve($0) }).flatMap(color) { theme.text = theme.text ?? c }
        if let c = vars["background-color"].map({ resolve($0) }).flatMap(color) { theme.background = theme.background ?? c }
        if let c = vars["handle-color"].map({ resolve($0) }).flatMap(color) { theme.handle = c }
        if let f = vars["font-family"] { theme.fontFamily = theme.fontFamily ?? resolve(f).replacingOccurrences(of: "\"", with: "") }
        if let s = vars["user-font-size"] ?? vars["base-font-size"], let v = Double(resolve(s).filter { "0123456789.".contains($0) }) { theme.fontSize = theme.fontSize ?? v }
        if let l = vars["line-height-multiple"], let v = Double(resolve(l)) { theme.lineHeight = theme.lineHeight ?? v }
        return theme
    }

    static func target(_ sel: String) -> Target? {
        let s = sel.replacingOccurrences(of: "'", with: "\"").replacingOccurrences(of: " ", with: "")
        if s == "editor" { return .editor }
        if s == "run[link]" { return .link }
        if s == "run[tag]" { return .anyTag }
        if let m = s.firstMatch(of: #/^run\[(?:tag|tagname)="?(?:data-)?([^"\]]+)"?\]$/#) { return .tag(String(m.1)) }
        if let m = s.firstMatch(of: #/^item\[data-type="?(project|task|note)"?\](?:>run\[content\])?$/#) { return ItemType(rawValue: String(m.1)).map { .type($0) } }
        if let m = s.firstMatch(of: #/^item\[data-([\w.-]+)\](?:>run\[content\])?$/#) { return .itemTag(String(m.1)) }
        return nil
    }

    static func style(_ p: [String: String]) -> Style {
        var s = Style()
        s.color = p["color"].flatMap(color)
        s.background = p["background-color"].flatMap(color)
        if let w = p["font-weight"] { s.bold = w == "bold" || (Int(w) ?? 400) >= 600 }
        if let st = p["font-style"] { s.italic = st == "italic" }
        if let d = p["text-decoration"] {
            s.strike = d.contains("line-through")
            s.underline = d.contains("underline")
        }
        if let st = p["text-strikethrough"] { s.strike = st != "none" && st != "NSUnderlineStyleNone" }
        if let sz = p["font-size"], let v = Double(sz.filter { "0123456789.".contains($0) }) { s.size = v }
        return s
    }

    // MARK: 색

    static let named: [String: NSColor] = [
        "black": .black, "white": .white, "red": .systemRed, "green": .systemGreen, "blue": .systemBlue,
        "orange": .systemOrange, "yellow": .systemYellow, "purple": .systemPurple, "gray": .gray, "grey": .gray,
        "pink": .systemPink, "brown": .systemBrown, "transparent": .clear,
    ]

    /// `#rgb`, `#rrggbb`, `rgb()`, `rgba()`, 이름, `mix()`·`lighten()`·`darken()`·`fade()`.
    static func color(_ raw: String) -> NSColor? {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if let c = named[s] { return c }
        if s.hasPrefix("#") {
            var hex = String(s.dropFirst())
            if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
            guard hex.count == 6, let v = Int(hex, radix: 16) else { return nil }
            return NSColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
        }
        guard let open = s.firstIndex(of: "("), s.hasSuffix(")") else { return nil }
        let fn = String(s[..<open])
        let args = splitArgs(String(s[s.index(after: open)..<s.index(before: s.endIndex)]))
        func pct(_ a: String) -> CGFloat { CGFloat(Double(a.replacingOccurrences(of: "%", with: "")) ?? 0) / (a.contains("%") ? 100 : 1) }
        switch fn {
        case "rgb", "rgba":
            let n = args.map { CGFloat(Double($0) ?? 0) }
            guard n.count >= 3 else { return nil }
            return NSColor(srgbRed: n[0] / 255, green: n[1] / 255, blue: n[2] / 255, alpha: n.count > 3 ? n[3] : 1)
        case "mix":
            guard args.count >= 2, let a = color(args[0])?.usingColorSpace(.sRGB), let b = color(args[1])?.usingColorSpace(.sRGB) else { return nil }
            let w = args.count > 2 ? pct(args[2]) : 0.5
            return NSColor(srgbRed: a.redComponent * w + b.redComponent * (1 - w), green: a.greenComponent * w + b.greenComponent * (1 - w),
                           blue: a.blueComponent * w + b.blueComponent * (1 - w), alpha: a.alphaComponent * w + b.alphaComponent * (1 - w))
        case "lighten", "darken":
            guard args.count == 2, let a = color(args[0]) else { return nil }
            let amount = pct(args[1])
            return fn == "lighten" ? a.blended(withFraction: amount, of: .white) : a.blended(withFraction: amount, of: .black)
        case "fade", "fadeout":
            guard args.count == 2, let a = color(args[0]) else { return nil }
            return a.withAlphaComponent(fn == "fade" ? pct(args[1]) : max(a.alphaComponent - pct(args[1]), 0))
        default: return nil
        }
    }

    private static func splitArgs(_ s: String) -> [String] {
        var out: [String] = [], cur = "", depth = 0
        for c in s {
            if c == "(" { depth += 1 } else if c == ")" { depth -= 1 }
            if c == ",", depth == 0 { out.append(cur.trimmingCharacters(in: .whitespaces)); cur = "" } else { cur.append(c) }
        }
        if !cur.isEmpty { out.append(cur.trimmingCharacters(in: .whitespaces)) }
        return out
    }
}
