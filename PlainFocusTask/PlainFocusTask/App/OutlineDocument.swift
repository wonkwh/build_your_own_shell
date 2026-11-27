import AppKit

/// `.taskpaper` 문서. 텍스트를 그대로 읽고 쓰며, 접기·포커스 상태는 파일 확장 속성에 둔다.
final class OutlineDocument: NSDocument {
    private(set) var editor = OutlineEditor(text: "")
    private var encoding: String.Encoding = .utf8
    private var pendingState: OutlineEditor.SavedState?
    nonisolated private static let stateAttribute = "com.wonkwh.PlainFocusTask.state"

    nonisolated override class var autosavesInPlace: Bool { true }

    override func makeWindowControllers() {
        addWindowController(DocumentWindowController(editor: editor))
        if let state = pendingState {
            editor.restore(state)
            pendingState = nil
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        guard let data = editor.string.data(using: encoding) ?? editor.string.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return data
    }

    nonisolated override func read(from data: Data, ofType typeName: String) throws {
        try MainActor.assumeIsolated {
            let text: String
            if let s = String(data: data, encoding: .utf8) {
                text = s
                encoding = .utf8
            } else {
                var converted: NSString?
                let raw = NSString.stringEncoding(for: data, encodingOptions: nil, convertedString: &converted, usedLossyConversion: nil)
                guard raw != 0, let converted else { throw CocoaError(.fileReadInapplicableStringEncoding) }
                text = converted as String
                encoding = String.Encoding(rawValue: raw)
            }
            if windowControllers.isEmpty {
                editor = OutlineEditor(text: text)
            } else {
                editor.replaceAll(text)
            }
        }
    }

    nonisolated override func read(from url: URL, ofType typeName: String) throws {
        try super.read(from: url, ofType: typeName)
        let state = Self.readState(url)
        MainActor.assumeIsolated {
            if windowControllers.isEmpty { pendingState = state } else if let state { editor.restore(state) }
        }
    }

    nonisolated override func write(to url: URL, ofType typeName: String) throws {
        try super.write(to: url, ofType: typeName)
        let state = MainActor.assumeIsolated { editor.savedState }
        Self.writeState(state, to: url)
    }

    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        let info = printInfo
        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        view.textStorage?.setAttributedString(editor.displayedAttributedString())
        view.sizeToFit()
        return NSPrintOperation(view: view, printInfo: info)
    }

    // MARK: 확장 속성

    nonisolated private static func readState(_ url: URL) -> OutlineEditor.SavedState? {
        url.withUnsafeFileSystemRepresentation { path -> OutlineEditor.SavedState? in
            guard let path else { return nil }
            let size = getxattr(path, stateAttribute, nil, 0, 0, 0)
            guard size > 0 else { return nil }
            var data = Data(count: size)
            let read = data.withUnsafeMutableBytes { getxattr(path, stateAttribute, $0.baseAddress, size, 0, 0) }
            guard read == size else { return nil }
            return try? JSONDecoder().decode(OutlineEditor.SavedState.self, from: data)
        }
    }

    nonisolated private static func writeState(_ state: OutlineEditor.SavedState, to url: URL) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            _ = data.withUnsafeBytes { setxattr(path, stateAttribute, $0.baseAddress, data.count, 0, 0) }
        }
    }
}
