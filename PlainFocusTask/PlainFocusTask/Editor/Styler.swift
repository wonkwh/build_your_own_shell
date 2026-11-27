import AppKit

extension NSAttributedString.Key {
    /// ⌘클릭으로 열 링크 주소
    static let outlineLink = NSAttributedString.Key("PFOutlineLink")
    /// ⌘클릭으로 필터를 걸 태그 이름
    static let outlineTag = NSAttributedString.Key("PFOutlineTag")
}

/// 사용자 설정. `UserDefaults` 키를 한곳에 모은다.
enum Preferences {
    static var fontSize: CGFloat { CGFloat(UserDefaults.standard.object(forKey: "fontSize") as? Double ?? 14) }
    static var fontFamily: String { UserDefaults.standard.string(forKey: "fontFamily") ?? "" }
    static var lineHeight: CGFloat { CGFloat(UserDefaults.standard.object(forKey: "lineHeight") as? Double ?? 1.25) }
    static var includeDateWhenDone: Bool { UserDefaults.standard.object(forKey: "includeDateWhenDone") as? Bool ?? true }
    static var archiveAddsProject: Bool { UserDefaults.standard.object(forKey: "archiveAddsProject") as? Bool ?? true }
    static var archiveRemovesTags: Bool { UserDefaults.standard.bool(forKey: "archiveRemovesTags") }
}

/// 줄 종류·태그·@done·링크 서식을 입힌다. 바뀐 줄만 다시 칠한다.
struct Styler {
    var scale: CGFloat = 1

    var baseFont: NSFont {
        let size = Preferences.fontSize * scale
        switch Preferences.fontFamily {
        case "serif": return NSFont(descriptor: NSFont.systemFont(ofSize: size).fontDescriptor.withDesign(.serif) ?? NSFont.systemFont(ofSize: size).fontDescriptor, size: size) ?? .systemFont(ofSize: size)
        case "mono": return .monospacedSystemFont(ofSize: size, weight: .regular)
        case "": return .systemFont(ofSize: size)
        default: return NSFont(name: Preferences.fontFamily, size: size) ?? .systemFont(ofSize: size)
        }
    }

    var indentWidth: CGFloat { (Preferences.fontSize * 1.25 * scale).rounded() }

    private static let linkRegex = try! NSRegularExpression(
        pattern: "\\b(?:[a-z][\\w\\-]+:(?:/{1,3}|[a-z0-9%.])|www\\d{0,3}[.])(?:[^\\s()<>]+|\\([^\\s()<>]+\\))+(?:\\([^\\s()<>]+\\)|[^`!()\\[\\]{};:'\".,<>?«»“”‘’\\s])|\\b[A-Z0-9._%+\\-]+@[A-Z0-9.\\-]+\\.[A-Z]{2,8}\\b|(?:^|(?<=\\s))~?\\.?/(?:\\\\\\s|[^\\s])+",
        options: [.caseInsensitive])

    func paragraphStyle(level: Int, type: ItemType, font: NSFont) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.defaultTabInterval = indentWidth
        p.tabStops = []
        let dash = type == .task ? ("- " as NSString).size(withAttributes: [.font: font]).width : 0
        p.headIndent = CGFloat(level) * indentWidth + dash
        p.lineHeightMultiple = Preferences.lineHeight
        p.paragraphSpacingBefore = type == .project && level == 0 ? (font.pointSize * 0.5).rounded() : 0
        return p
    }

    func style(_ storage: NSTextStorage, _ index: LineIndex, lines: ClosedRange<Int>) {
        let text = storage.mutableString
        let base = baseFont
        let fm = NSFontManager.shared
        let bold = fm.convert(base, toHaveTrait: .boldFontMask)
        let italic = fm.convert(base, toHaveTrait: .italicFontMask)
        for i in lines where i < index.count {
            let line = index[i]
            let font = line.type == .project ? bold : line.type == .note ? italic : base
            let full = line.fullRange
            guard full.length > 0 else { continue }
            storage.setAttributes([
                .font: font,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle(level: line.level, type: line.type, font: font),
            ], range: full)
            if line.tag("done") != nil, line.contentEnd > line.indentLength {
                let content = NSRange(location: line.bodyStart, length: line.contentEnd - line.indentLength)
                storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                       .foregroundColor: NSColor.secondaryLabelColor], range: content)
            }
            for tag in line.tags {
                let r = NSRange(location: line.start + tag.range.location, length: tag.range.length)
                storage.addAttributes([.font: base, .foregroundColor: NSColor.secondaryLabelColor, .outlineTag: tag.name], range: r)
            }
            let body = NSRange(location: line.bodyStart, length: line.length - line.indentLength)
            if body.length > 4 {
                let bodyText = text.substring(with: body)
                Self.linkRegex.enumerateMatches(in: bodyText, range: NSRange(location: 0, length: body.length)) { m, _, _ in
                    guard let local = m?.range else { return }
                    let r = NSRange(location: body.location + local.location, length: local.length)
                    let s = (bodyText as NSString).substring(with: local)
                    let url = s.contains("@") && !s.contains(":") ? "mailto:" + s : s.hasPrefix("www") ? "http://" + s : s
                    storage.addAttributes([.foregroundColor: NSColor.linkColor, .outlineLink: url,
                                           .underlineStyle: NSUnderlineStyle.single.rawValue], range: r)
                }
            }
        }
    }
}
