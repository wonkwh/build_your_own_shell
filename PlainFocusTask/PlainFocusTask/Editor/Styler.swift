import AppKit

extension NSAttributedString.Key {
    /// 클릭하면 열 링크 주소
    static let outlineLink = NSAttributedString.Key("PFOutlineLink")
    /// 클릭하면 필터를 걸 태그 이름
    static let outlineTag = NSAttributedString.Key("PFOutlineTag")
    /// 클릭하면 태그와 값으로 필터를 건다
    static let outlineTagValue = NSAttributedString.Key("PFOutlineTagValue")
    /// 작업 앞 `- `. 클릭하면 @done 토글
    static let outlineDash = NSAttributedString.Key("PFOutlineDash")
}

/// 사용자 설정. `UserDefaults` 키를 한곳에 모은다.
enum Preferences {
    static var fontSize: CGFloat { CGFloat(UserDefaults.standard.object(forKey: "fontSize") as? Double ?? 14) }
    static var fontFamily: String { UserDefaults.standard.string(forKey: "fontFamily") ?? "" }
    static var lineHeight: CGFloat { CGFloat(UserDefaults.standard.object(forKey: "lineHeight") as? Double ?? 1.25) }
    static var includeDateWhenDone: Bool { UserDefaults.standard.object(forKey: "includeDateWhenDone") as? Bool ?? true }
    static var archiveAddsProject: Bool { UserDefaults.standard.object(forKey: "archiveAddsProject") as? Bool ?? true }
    static var archiveRemovesTags: Bool { UserDefaults.standard.bool(forKey: "archiveRemovesTags") }
    static var styleSheet: String { UserDefaults.standard.string(forKey: "styleSheet") ?? "기본" }
}

/// 줄 종류·태그·@done·링크 서식을 입힌다. 바뀐 줄만 다시 칠한다.
struct Styler {
    var scale: CGFloat = 1
    var theme = Theme()

    var baseFont: NSFont {
        let size = (theme.fontSize ?? Preferences.fontSize) * scale
        let family = Preferences.fontFamily.isEmpty ? (theme.fontFamily ?? "") : Preferences.fontFamily
        switch family {
        case "serif":
            let d = NSFont.systemFont(ofSize: size).fontDescriptor.withDesign(.serif)
            return d.flatMap { NSFont(descriptor: $0, size: size) } ?? .systemFont(ofSize: size)
        case "mono": return .monospacedSystemFont(ofSize: size, weight: .regular)
        case "", "-apple-system", "system": return .systemFont(ofSize: size)
        default: return NSFont(name: family, size: size) ?? .systemFont(ofSize: size)
        }
    }

    var indentWidth: CGFloat { ((theme.fontSize ?? Preferences.fontSize) * 1.25 * scale).rounded() }
    var textColor: NSColor { theme.text ?? .labelColor }
    var secondaryColor: NSColor { theme.text?.withAlphaComponent(0.55) ?? .secondaryLabelColor }
    var tintColor: NSColor { theme.tint ?? .controlAccentColor }

    private static let linkRegex = try! NSRegularExpression(
        pattern: "\\b(?:[a-z][\\w\\-]+:(?:/{1,3}|[a-z0-9%.])|www\\d{0,3}[.])(?:[^\\s()<>]+|\\([^\\s()<>]+\\))+(?:\\([^\\s()<>]+\\)|[^`!()\\[\\]{};:'\".,<>?«»“”‘’\\s])|\\b[A-Z0-9._%+\\-]+@[A-Z0-9.\\-]+\\.[A-Z]{2,8}\\b|(?:^|(?<=\\s))~?\\.?/(?:\\\\\\s|[^\\s])+",
        options: [.caseInsensitive])

    func paragraphStyle(level: Int, type: ItemType, font: NSFont) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.defaultTabInterval = indentWidth
        p.tabStops = []
        let dash = type == .task ? ("- " as NSString).size(withAttributes: [.font: font]).width : 0
        p.headIndent = CGFloat(level) * indentWidth + dash
        p.lineHeightMultiple = theme.lineHeight ?? Preferences.lineHeight
        p.paragraphSpacingBefore = type == .project && level == 0 ? (font.pointSize * 0.5).rounded() : 0
        return p
    }

    private func font(_ base: NSFont, _ s: Theme.Style?, bold: Bool, italic: Bool) -> NSFont {
        var f = base
        if let size = s?.size { f = NSFont(descriptor: f.fontDescriptor, size: size * scale) ?? f }
        let fm = NSFontManager.shared
        if s?.bold ?? bold { f = fm.convert(f, toHaveTrait: .boldFontMask) }
        if s?.italic ?? italic { f = fm.convert(f, toHaveTrait: .italicFontMask) }
        return f
    }

    private func apply(_ s: Theme.Style?, to storage: NSTextStorage, _ r: NSRange) {
        guard let s, r.length > 0 else { return }
        if let c = s.color { storage.addAttribute(.foregroundColor, value: c, range: r) }
        if let b = s.background { storage.addAttribute(.backgroundColor, value: b, range: r) }
        if let st = s.strike { storage.addAttribute(.strikethroughStyle, value: st ? NSUnderlineStyle.single.rawValue : 0, range: r) }
        if let u = s.underline { storage.addAttribute(.underlineStyle, value: u ? NSUnderlineStyle.single.rawValue : 0, range: r) }
    }

    func style(_ storage: NSTextStorage, _ index: LineIndex, lines: ClosedRange<Int>) {
        let text = storage.mutableString
        let base = baseFont
        for i in lines where i < index.count {
            let line = index[i]
            let full = line.fullRange
            guard full.length > 0 else { continue }
            let typeStyle = theme.style(.type(line.type))
            let font = font(base, typeStyle, bold: line.type == .project, italic: line.type == .note)
            storage.setAttributes([
                .font: font,
                .foregroundColor: line.type == .note ? secondaryColor : textColor,
                .paragraphStyle: paragraphStyle(level: line.level, type: line.type, font: font),
            ], range: full)
            apply(typeStyle, to: storage, full)
            let content = NSRange(location: line.bodyStart, length: max(line.contentEnd - line.indentLength, 0))
            if line.type == .task, line.length - line.indentLength >= 2 {
                storage.addAttribute(.outlineDash, value: true, range: NSRange(location: line.bodyStart, length: 2))
            }
            if line.tag("done") != nil {
                storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: secondaryColor], range: content)
            }
            for tag in line.tags {
                if let s = theme.style(.itemTag(tag.name)) {
                    apply(s, to: storage, content)
                    if s.bold != nil || s.italic != nil || s.size != nil {
                        storage.addAttribute(.font, value: self.font(font, s, bold: false, italic: false), range: content)
                    }
                }
            }
            for tag in line.tags {
                let r = NSRange(location: line.start + tag.range.location, length: tag.range.length)
                let tagStyle = theme.style(.tag(tag.name)) ?? theme.style(.anyTag)
                storage.addAttributes([.font: base, .foregroundColor: secondaryColor, .outlineTag: tag.name], range: r)
                apply(tagStyle, to: storage, r)
                if let value = tag.value, !value.isEmpty {
                    let nameLength = (tag.name as NSString).length + 2
                    let valueRange = NSRange(location: r.location + nameLength, length: max(r.length - nameLength - 1, 0))
                    storage.addAttribute(.outlineTagValue, value: value, range: valueRange)
                }
            }
            let body = NSRange(location: line.bodyStart, length: line.length - line.indentLength)
            if body.length > 4 {
                let bodyText = text.substring(with: body)
                Self.linkRegex.enumerateMatches(in: bodyText, range: NSRange(location: 0, length: body.length)) { m, _, _ in
                    guard let local = m?.range else { return }
                    let r = NSRange(location: body.location + local.location, length: local.length)
                    let s = (bodyText as NSString).substring(with: local)
                    let url = s.contains("@") && !s.contains(":") ? "mailto:" + s : s.hasPrefix("www") ? "http://" + s : s
                    storage.addAttributes([.foregroundColor: theme.style(.link)?.color ?? tintColor, .outlineLink: url,
                                           .underlineStyle: NSUnderlineStyle.single.rawValue], range: r)
                }
            }
        }
    }
}
