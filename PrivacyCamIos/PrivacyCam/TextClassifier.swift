import Foundation

/// OCR 한 줄을 민감 정보 카테고리로 분류한다. 정규식은 Flutter 원본과 같다.
enum TextClassifier {
    private static func re(_ p: String, ci: Bool = true) -> NSRegularExpression {
        try! NSRegularExpression(pattern: p, options: ci ? [.caseInsensitive] : [])
    }

    private static let email = re(#"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#)
    private static let phone = re(#"(?<!\w)(?:\+?\d{1,3}[\s.-]?)?(?:\(?\d{2,4}\)?[\s.-]?)\d{3,4}[\s.-]?\d{4}(?!\w)"#)
    private static let card = re(#"(?<!\d)(?:\d[ -]?){13,19}(?!\d)"#)
    private static let url = re(#"(?<![@\w])(?:(?:https?://|www\.)[^\s]+|[a-z0-9-]+(?:\.[a-z0-9-]+)+(?::\d+)?(?:/[^\s]*)?)"#)
    private static let addressLabel = re(#"\b(?:address|billing\s+address|delivery\s+address|shipping\s+address|residential\s+address|location|current\s+location|based\s+in|located\s+in)\b\s*:?"#)
    private static let streetAddress = re(#"\b(?:\d{1,6}[A-Z]?\s+)?(?:[A-Z0-9][A-Z0-9.'-]*\s+){0,7}(?:street|st|road|rd|avenue|ave|lane|ln|drive|dr|boulevard|blvd|court|ct|place|pl|terrace|trail|highway|hwy|way)\b(?:\s*[,#-]?\s*(?:apt|apartment|suite|unit|flat|floor)\s*[A-Z0-9-]+)?"#)
    private static let structuredAddress = re(#"\b(?:house|flat|plot|apartment|apt|suite|unit|block|sector|phase|floor)\s*(?:no\.?\s*)?[A-Z0-9-]+"#)
    private static let poBox = re(#"\bP\.?\s*O\.?\s+BOX\s+\d+\b"#)
    private static let postalLocation = re(#"\b(?:[A-Z][A-Z .'-]+,\s*)?[A-Z]{2}\s+\d{5}(?:-\d{4})?\b|\b[A-Z]\d[A-Z]\s?\d[A-Z]\d\b|\b[A-Z]{1,2}\d[A-Z\d]?\s*\d[A-Z]{2}\b"#)
    private static let cityLocation = re(#"^\s*(?:islamabad|rawalpindi|lahore|karachi|peshawar|quetta|faisalabad|multan|sialkot|gujranwala|hyderabad|abu\s+dhabi|dubai|sharjah|ajman|al\s+ain|ras\s+al\s+khaimah|fujairah|umm\s+al\s+quwain|riyadh|jeddah|doha|muscat|manama|kuwait\s+city|cairo|amman|beirut|istanbul|london|paris|berlin|madrid|rome|amsterdam|brussels|vienna|zurich|geneva|stockholm|oslo|copenhagen|helsinki|dublin|lisbon|prague|warsaw|budapest|athens|singapore|tokyo|seoul|beijing|shanghai|hong\s+kong|bangkok|kuala\s+lumpur|jakarta|manila|new\s+delhi|delhi|mumbai|bengaluru|bangalore|toronto|vancouver|montreal|new\s+york|los\s+angeles|san\s+francisco|chicago|boston|seattle|austin|sydney|melbourne|brisbane|auckland|cape\s+town|johannesburg|nairobi)(?:\s*(?:,|[-–])\s*[a-z][a-z .'-]{1,40})?\s*$"#)
    private static let securityCodeLabel = re(#"\b(?:CVV2?|CVC2?|CID|CSC|CARD\s+SECURITY\s+CODE|SECURITY\s+CODE)\b"#)
    private static let expiryDate = re(#"(?<!\d)(?:0?[1-9]|1[0-2])\s*[/\-]\s*\d{2,4}(?!\d)"#)
    private static let validityLabel = re(#"\b(?:VALID|VAL[I1]D|THRU|THROUGH|EXP|EXPIRES?|EXPIRY)\b"#)
    private static let possibleSecurityCode = re(#"(?<!\d)\d{3,4}(?!\d)"#)
    private static let trailingCode = re(#"(?<!\d)\d{3,4}[^\d]*$"#)

    static func classify(_ text: String) -> RedactionCategory {
        if email.matches(text) { return .email }
        if isSecurityCodeLabel(text) || isSecurityContext(text) { return .cardSecurityCode }
        for match in card.allMatches(text) {
            let digits = match.filter(\.isNumber)
            if (13...19).contains(digits.count), passesLuhn(digits) { return .card }
        }
        if phone.matches(text) { return .phone }
        if url.matches(text) { return .url }
        if isAddressLabel(text) || looksLikeAddress(text) { return .address }
        return .otherText
    }

    static func isAddressLabel(_ text: String) -> Bool { addressLabel.matches(text) }

    static func looksLikeAddress(_ text: String) -> Bool {
        [streetAddress, structuredAddress, poBox, postalLocation, cityLocation].contains { $0.matches(text) }
    }

    static func hasPossibleSecurityCode(_ text: String) -> Bool { possibleSecurityCode.matches(text) }

    /// OCR 이 CVC/CVV 의 한 글자를 잘못 읽어도 보안코드 라벨로 본다.
    static func isSecurityCodeLabel(_ text: String) -> Bool {
        if securityCodeLabel.matches(text) { return true }
        let words = text.uppercased().split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
        return words.contains { w in
            var word = String(w)
            if word.count == 4, word.hasSuffix("2") { word.removeLast() }
            return word.count == 3 && (oneEditOrLess(word, "CVC") || oneEditOrLess(word, "CVV"))
        }
    }

    static func isSecurityContext(_ text: String) -> Bool {
        let expiries = expiryDate.allMatches(text).count
        guard expiries > 0, trailingCode.matches(text) else { return false }
        return validityLabel.matches(text) || expiries >= 2
    }

    static func passesLuhn(_ digits: String) -> Bool {
        guard !digits.isEmpty, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber) else { return false }
        var sum = 0
        for (i, ch) in digits.reversed().enumerated() {
            var v = ch.wholeNumberValue!
            if i.isMultiple(of: 2) == false { v *= 2; if v > 9 { v -= 9 } }
            sum += v
        }
        return sum % 10 == 0
    }

    private static func oneEditOrLess(_ a: String, _ b: String) -> Bool {
        a.count == b.count && zip(a, b).filter { $0 != $1 }.count <= 1
    }
}

private extension NSRegularExpression {
    func matches(_ s: String) -> Bool {
        firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    func allMatches(_ s: String) -> [String] {
        matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { Range($0.range, in: s).map { String(s[$0]) } }
    }
}
