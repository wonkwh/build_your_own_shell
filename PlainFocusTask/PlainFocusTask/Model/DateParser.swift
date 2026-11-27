import Foundation

/// TaskPaper 자연어 날짜(`date-time-parser.pegjs`)를 해석한다.
enum DateParser {
    nonisolated(unsafe) static var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }()

    /// - Returns: 해석 실패 시 nil. 문법 전체를 소비해야 성공한다.
    static func parse(_ string: String, now: Date = .now) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        var p = Parser(chars: Array(trimmed.lowercased()), now: now)
        if let date = p.expression() { return date }
        return iso8601(trimmed)
    }

    /// 시각이 있으면 `yyyy-MM-dd HH:mm`, 없으면 `yyyy-MM-dd`.
    static func format(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let day = String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
        if c.hour! == 0 && c.minute! == 0 { return day }
        return day + String(format: " %02d:%02d", c.hour!, c.minute!)
    }

    private static func iso8601(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.timeZone = calendar.timeZone
        for options: ISO8601DateFormatter.Options in [[.withInternetDateTime], [.withFullDate, .withTime, .withColonSeparatorInTime, .withDashSeparatorInDate]] {
            f.formatOptions = options
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    fileprivate struct Duration {
        var component: Calendar.Component
        var value: Int
    }

    fileprivate struct Parser {
        let chars: [Character]
        let now: Date
        var pos = 0
        var cal: Calendar { DateParser.calendar }

        mutating func expression() -> Date? {
            let date = parseDate()
            ws()
            let time = parseTime()
            ws()
            var durations: [Duration] = []
            while let d = parseDuration() { durations.append(d); ws() }
            guard pos == chars.count else { return nil }
            var result = date ?? now
            if let time { result = cal.startOfDay(for: result).addingTimeInterval(time) }
            for d in durations { result = add(d, to: result) }
            return result
        }

        // MARK: 기본 도구

        mutating func ws() { while pos < chars.count, chars[pos].isWhitespace { pos += 1 } }

        func peek(_ s: String) -> Bool {
            var i = pos
            for c in s {
                guard i < chars.count, chars[i] == c else { return false }
                i += 1
            }
            return true
        }

        mutating func lit(_ s: String) -> Bool {
            guard peek(s) else { return false }
            pos += s.count
            return true
        }

        mutating func integer() -> Int? {
            let start = pos
            while pos < chars.count, chars[pos].isASCII, chars[pos].isNumber { pos += 1 }
            return pos > start ? Int(String(chars[start..<pos])) : nil
        }

        /// 실패하면 위치를 되돌린다.
        mutating func attempt<T>(_ body: (inout Parser) -> T?) -> T? {
            let save = pos
            if let r = body(&self) { return r }
            pos = save
            return nil
        }

        // MARK: 날짜

        mutating func parseDate() -> Date? {
            attempt { $0.absoluteDate() } ?? attempt { $0.relativeDate() }
        }

        mutating func absoluteDate() -> Date? {
            guard let year = integer() else { return nil }
            ws()
            if attempt({ $0.durationUnit() }) != nil { return nil }
            ws()
            if attempt({ $0.period() }) != nil { return nil }
            ws()
            if peek(":") { return nil }
            var month = 1, day = 1
            if let m = attempt({ p -> Int? in p.lit("-") ? p.integer() : nil }) {
                month = m
                if let d = attempt({ p -> Int? in p.lit("-") ? p.integer() : nil }) { day = d }
            }
            return cal.date(from: DateComponents(year: year, month: month, day: day))
        }

        mutating func relativeDate() -> Date? {
            let today = cal.startOfDay(for: now)
            if lit("now") { return now }
            if lit("yesterday") { return cal.date(byAdding: .day, value: -1, to: today) }
            if lit("today") { return today }
            if lit("tomorrow") { return cal.date(byAdding: .day, value: 1, to: today) }
            return attempt { $0.relativeMonth() } ?? attempt { $0.relativeDayOfWeek() } ?? attempt { $0.relativeDuration() }
        }

        mutating func specifier() -> Int? {
            if lit("this") { return 0 }
            if lit("next") { return 1 }
            if lit("last") { return -1 }
            return nil
        }

        static let months: [(String, Int)] = [
            ("january", 1), ("jan", 1), ("february", 2), ("feb", 2), ("march", 3), ("mar", 3), ("april", 4), ("apr", 4),
            ("may", 5), ("june", 6), ("jun", 6), ("july", 7), ("jul", 7), ("august", 8), ("aug", 8),
            ("september", 9), ("sep", 9), ("october", 10), ("oct", 10), ("november", 11), ("nov", 11),
            ("december", 12), ("dec", 12),
        ]

        mutating func relativeMonth() -> Date? {
            let spec = attempt { $0.specifier() } ?? 0
            ws()
            guard let month = Self.months.first(where: { lit($0.0) })?.1 else { return nil }
            ws()
            let day = attempt { $0.integer() } ?? 1
            var c = cal.dateComponents([.year], from: now)
            c.month = month
            c.day = day
            guard let date = cal.date(from: c) else { return nil }
            return cal.date(byAdding: .year, value: spec, to: date)
        }

        static let weekdays: [(String, Int)] = [
            ("monday", 1), ("mon", 1), ("tuesday", 2), ("tue", 2), ("wednesday", 3), ("wed", 3), ("thursday", 4), ("thu", 4),
            ("friday", 5), ("fri", 5), ("saturday", 6), ("sat", 6), ("sunday", 7), ("sun", 7),
        ]

        mutating func relativeDayOfWeek() -> Date? {
            let spec = attempt { $0.specifier() } ?? 0
            ws()
            if peek("mont") { return nil }
            guard let day = Self.weekdays.first(where: { lit($0.0) })?.1 else { return nil }
            let today = cal.startOfDay(for: now)
            let iso = (cal.component(.weekday, from: today) + 5) % 7 + 1
            return cal.date(byAdding: .day, value: day - iso + spec * 7, to: today)
        }

        mutating func relativeDuration() -> Date? {
            guard let spec = specifier() else { return nil }
            ws()
            guard let unit = durationUnit() else { return nil }
            let start = startOf(unit, now)
            return unit == .quarter ? cal.date(byAdding: .month, value: spec * 3, to: start) : cal.date(byAdding: unit, value: spec, to: start)
        }

        func startOf(_ unit: Calendar.Component, _ date: Date) -> Date {
            switch unit {
            case .nanosecond: return date
            case .second, .minute, .hour, .day:
                let all: [Calendar.Component] = [.year, .month, .day, .hour, .minute, .second]
                let keep = all.prefix(through: all.firstIndex(of: unit)!)
                return cal.date(from: cal.dateComponents(Set(keep), from: date))!
            case .weekOfYear:
                let today = cal.startOfDay(for: date)
                let iso = (cal.component(.weekday, from: today) + 5) % 7 + 1
                return cal.date(byAdding: .day, value: 1 - iso, to: today)!
            case .month: return cal.date(from: cal.dateComponents([.year, .month], from: date))!
            case .quarter:
                var c = cal.dateComponents([.year, .month], from: date)
                c.month = (c.month! - 1) / 3 * 3 + 1
                return cal.date(from: c)!
            default: return cal.date(from: cal.dateComponents([.year], from: date))!
            }
        }

        // MARK: 시각·기간

        mutating func period() -> Int? {
            if lit("pm") { return 12 }
            if lit("am") { return 0 }
            return nil
        }

        /// 자정 기준 초
        mutating func parseTime() -> TimeInterval? {
            attempt { p -> TimeInterval? in
                p.ws()
                _ = p.lit("at")
                p.ws()
                guard let h = p.integer() else { return nil }
                p.ws()
                guard let add = p.period() else { return nil }
                return TimeInterval(Self.hour(h, add) * 3600)
            } ?? attempt { p -> TimeInterval? in
                guard let h = p.integer(), p.lit(":"), let m = p.integer() else { return nil }
                var s = 0, ms = 0
                if let v = p.attempt({ q -> Int? in q.lit(":") ? q.integer() : nil }) {
                    s = v
                    if let v2 = p.attempt({ q -> Int? in q.lit(":") ? q.integer() : nil }) { ms = v2 }
                }
                p.ws()
                let add = p.attempt { $0.period() } ?? 0
                return TimeInterval(Self.hour(h, add) * 3600 + m * 60 + s) + TimeInterval(ms) / 1000
            }
        }

        /// 12am은 0시, 12pm은 12시로 고친다(TaskPaper는 24시로 계산).
        static func hour(_ h: Int, _ add: Int) -> Int { h == 12 ? add : h + add }

        mutating func parseDuration() -> Duration? {
            attempt { p -> Duration? in
                var sign = 1
                if p.lit("-") { sign = -1 } else { _ = p.lit("+") }
                p.ws()
                guard let n = p.integer() else { return nil }
                p.ws()
                guard let unit = p.durationUnit() else { return nil }
                return unit == .nanosecond ? Duration(component: .nanosecond, value: sign * n * 1_000_000)
                    : unit == .quarter ? Duration(component: .month, value: sign * n * 3)
                    : Duration(component: unit, value: sign * n)
            }
        }

        mutating func durationUnit() -> Calendar.Component? {
            func any(_ p: inout Parser, _ words: [String]) -> Bool { words.contains { p.lit($0) } }
            if any(&self, ["milliseconds", "millisecond", "ms"]) { return .nanosecond }
            if any(&self, ["seconds", "second", "sec"]) || (!peek("sa") && !peek("su") && lit("s")) { return .second }
            if any(&self, ["minutes", "minute", "mins", "min"]) || (!peek("mo") && !peek("ma") && lit("m")) { return .minute }
            if any(&self, ["hours", "hour", "h"]) { return .hour }
            if any(&self, ["days", "day"]) || (!peek("de") && lit("d")) { return .day }
            if any(&self, ["weeks", "week"]) || (!peek("we") && lit("w")) { return .weekOfYear }
            if any(&self, ["months", "month"]) || (!peek("oc") && lit("o")) { return .month }
            if any(&self, ["quarters", "quarter", "q"]) { return .quarter }
            if any(&self, ["years", "year", "y"]) { return .year }
            return nil
        }

        func add(_ d: Duration, to date: Date) -> Date {
            cal.date(byAdding: d.component, value: d.value, to: date) ?? date
        }
    }
}
