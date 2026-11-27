import AppKit

/// 자연어 날짜 입력 시트. 입력하는 동안 해석한 날짜를 보여 준다.
final class DatePrompt: NSObject, NSTextFieldDelegate {
    private static var current: DatePrompt?

    private let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 330), styleMask: [.titled], backing: .buffered, defer: false)
    private let field = NSTextField()
    private let preview = NSTextField(labelWithString: "")
    private let picker = NSDatePicker()
    private let completion: (String?) -> Void
    private var value: String?

    static func ask(over window: NSWindow, title: String, completion: @escaping (String?) -> Void) {
        let prompt = DatePrompt(title: title, completion: completion)
        current = prompt
        window.beginSheet(prompt.sheet) { _ in
            current = nil
        }
        prompt.sheet.makeFirstResponder(prompt.field)
    }

    private init(title: String, completion: @escaping (String?) -> Void) {
        self.completion = completion
        super.init()
        let label = NSTextField(labelWithString: title)
        label.font = .boldSystemFont(ofSize: 13)
        field.placeholderString = "today, tomorrow, next fri, +3d, 2026-12-01 5pm"
        field.delegate = self
        preview.textColor = .secondaryLabelColor
        picker.datePickerStyle = .clockAndCalendar
        picker.datePickerElements = [.yearMonthDay]
        picker.dateValue = DateParser.calendar.startOfDay(for: .now)
        picker.target = self
        picker.action = #selector(pickerChanged)
        let cancel = NSButton(title: "취소", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let ok = NSButton(title: "확인", target: self, action: #selector(confirm))
        ok.keyEquivalent = "\r"
        let buttons = NSStackView(views: [cancel, ok])
        let stack = NSStackView(views: [label, field, preview, picker, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        field.widthAnchor.constraint(equalToConstant: 288).isActive = true
        sheet.contentView = stack
        update(from: picker.dateValue, text: false)
    }

    private func update(from date: Date, text: Bool) {
        value = DateParser.format(date)
        preview.stringValue = "→ " + (value ?? "")
        if text { field.stringValue = value ?? "" }
    }

    func controlTextDidChange(_ obj: Notification) {
        let s = field.stringValue
        if s.trimmingCharacters(in: .whitespaces).isEmpty {
            update(from: picker.dateValue, text: false)
        } else if let date = DateParser.parse(s) {
            picker.dateValue = date
            update(from: date, text: false)
        } else {
            value = nil
            preview.stringValue = "해석할 수 없는 날짜"
        }
    }

    @objc private func pickerChanged() { update(from: DateParser.calendar.startOfDay(for: picker.dateValue), text: true) }

    @objc private func confirm() {
        guard let value else { NSSound.beep(); return }
        finish(value)
    }

    @objc private func cancel() { finish(nil) }

    private func finish(_ result: String?) {
        sheet.sheetParent?.endSheet(sheet)
        completion(result)
    }
}
