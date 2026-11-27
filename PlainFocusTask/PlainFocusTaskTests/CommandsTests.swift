import Foundation
import Testing

/// `|`는 커서, `[ ]`는 선택. `hidden`은 숨길 줄 번호.
@MainActor
private func run(_ doc: String, hidden: Set<Int> = [], _ f: (EditorSnapshot) -> Edit?) -> String? {
    var s = doc
    var sel = NSRange(location: 0, length: 0)
    if let r = s.range(of: "|") {
        sel.location = s.utf16.distance(from: s.utf16.startIndex, to: r.lowerBound.samePosition(in: s.utf16)!)
        s.removeSubrange(r)
    } else if let a = s.range(of: "[") {
        let start = s.utf16.distance(from: s.utf16.startIndex, to: a.lowerBound.samePosition(in: s.utf16)!)
        s.removeSubrange(a)
        let b = s.range(of: "]")!
        let end = s.utf16.distance(from: s.utf16.startIndex, to: b.lowerBound.samePosition(in: s.utf16)!)
        s.removeSubrange(b)
        sel = NSRange(location: start, length: end - start)
    }
    let text = s as NSString
    let index = LineIndex(text)
    let snap = EditorSnapshot(text: text, index: index, hidden: (0..<index.count).map { hidden.contains($0) }, selection: sel)
    guard let edit = f(snap) else { return nil }
    let out = NSMutableString(string: s)
    out.replaceCharacters(in: edit.range, with: edit.text)
    if edit.selection.length == 0 {
        out.insert("|", at: edit.selection.location)
    } else {
        out.insert("]", at: NSMaxRange(edit.selection))
        out.insert("[", at: edit.selection.location)
    }
    return out as String
}

@MainActor
@Suite struct CommandsTests {
    @Test func indentOutdent() {
        #expect(run("A\n|B\nC") { $0.shiftLines(1) } == "A\n\t|B\nC")
        #expect(run("A\n|B\n\tc\nD", hidden: [2]) { $0.shiftLines(1) } == "A\n\t|B\n\t\tc\nD")
        #expect(run("A\n\t|B") { $0.shiftLines(-1) } == "A\n|B")
        #expect(run("|A") { $0.shiftLines(-1) } == nil)
        #expect(run("[A\nB]") { $0.shiftLines(1) } == "\t[A\n\tB]")
    }

    @Test func moveLines() {
        #expect(run("A\nB\n|C") { $0.moveLines(up: true) } == "A\n|C\nB")
        #expect(run("|A\nB\nC") { $0.moveLines(up: false) } == "B\n|A\nC")
        #expect(run("A\n\ta\nB\n\tb\n|C", hidden: [1, 3]) { $0.moveLines(up: true) } == "A\n\ta\n|C\nB\n\tb")
        #expect(run("|A") { $0.moveLines(up: true) } == nil)
    }

    @Test func moveBranches() {
        #expect(run("|A\n\ta\nB\nC") { $0.moveBranches(up: false) } == "B\n|A\n\ta\nC")
        #expect(run("A\n|B\n\tb") { $0.moveBranches(up: true) } == "|B\n\tb\nA")
        #expect(run("A\n|B\n\tb") { $0.shiftBranches(1) } == "A\n\t|B\n\t\tb")
        #expect(run("P\n\t|A\n\t\ta\n\tB") { $0.shiftBranches(-1) } == "P\n\tB\n|A\n\ta")
        #expect(run("|A") { $0.shiftBranches(1) } == nil)
    }

    @Test func groupDuplicateDelete() {
        #expect(run("[A\nB]") { $0.groupLines() } == "|\n\tA\n\tB")
        #expect(run("\t|A\nB") { $0.groupLines() } == "\t|\n\t\tA\nB")
        #expect(run("|A\nB") { $0.duplicateLines() } == "A\n|A\nB")
        #expect(run("A\n|B\nC") { $0.deleteLines() } == "A\n|C")
        #expect(run("A\n|B") { $0.deleteLines() } == "|A")
        #expect(run("|A") { $0.deleteLines() } == "|")
    }

    @Test func formatAndTags() {
        #expect(run("|A") { $0.format(as: .task) } == "- |A")
        #expect(run("- A| @t") { $0.format(as: .project) } == "A|: @t")
        #expect(run("\tP|: @t") { $0.format(as: .note) } == "\tP| @t")
        #expect(run("- a|") { $0.toggleTag("done") } == "- a| @done")
        #expect(run("- a| @done(2026-01-01) @x") { $0.toggleTag("done") } == "- a| @x")
        #expect(run("[- a\n- b @done]") { $0.toggleTag("done") } == "[- a @done\n- b @done]")
        #expect(run("- a|") { $0.toggleTag("due", value: "2026-11-28") } == "- a| @due(2026-11-28)")
        #expect(run("- a @due(x)|") { $0.setTag("due", value: "y", remove: false) } == "- a @due(y)|")
        #expect(run("- a @x @y(1)|") { $0.clearTags() } == "- a|")
        #expect(run("@a b|") { $0.toggleTag("a") } == "b|")
    }

    @Test func archive() {
        #expect(run("P:\n\t- a @done\n\t- b|\n") { $0.archiveDone() } == "P:\n\t- b|\nArchive:\n\t- a @done @project(P)\n")
        #expect(run("P:\n\tQ:\n\t\t- a @done\n|Archive:\n\t- old @done") { $0.archiveDone() }
            == "P:\n\tQ:\n|Archive:\n\t- a @done @project(P / Q)\n\t- old @done")
        #expect(run("- a @done @x|") { $0.archiveDone(addProjectTag: false, removeExtraTags: true) } == "|Archive:\n\t- a @done")
        #expect(run("|- a") { $0.archiveDone() } == nil)
    }

    @Test func moveToProject() {
        #expect(run("A:\nB:\n|- x") { $0.moveToProject(0) } == "A:\n\t- |x\nB:")
        #expect(run("A:\n\t|- x") { $0.moveToProject(nil) } == "- |x\nA:")
        #expect(run("A:\n\t|- x") { $0.moveToProject(nil, newProject: "New") } == "New:\n\t- |x\nA:")
        #expect(run("|A:\n\tB:") { $0.moveToProject(1) } == nil)
    }

    @Test func newline() {
        #expect(run("- abc|") { $0.insertNewline() } == "- abc\n- |")
        #expect(run("\t- |") { $0.insertNewline() } == "\t|")
        #expect(run("|- abc") { $0.insertNewline() } == "\n|- abc")
        #expect(run("- ab|c") { $0.insertNewline() } == "- ab\n- |c")
        #expect(run("P:|\n\t- a") { $0.insertNewline() } == "P:\n\t|\n\t- a")
        #expect(run("P:|\n\t- a", hidden: [1]) { $0.insertNewline() } == "P:\n\t- a\n|")
        #expect(run("note|") { $0.insertNewline() } == "note\n|")
    }

    @Test func backspace() {
        #expect(run("A\n\t|b") { $0.deleteBackward() } == "A\n|b")
        #expect(run("A\n\ta\n|B", hidden: [1]) { $0.deleteBackward() } == "A|B\n\ta")
        #expect(run("A\n|B") { $0.deleteBackward() } == nil)
        #expect(run("A\nB|") { $0.deleteBackward() } == nil)
    }

    @Test func insertItem() {
        #expect(run("|A") { $0.insertItem("- New Task", selectFrom: 2, selectTo: 10) } == "A\n- [New Task]")
        #expect(run("|P:\n\t- a") { $0.insertItem("New Note", selectFrom: 0, selectTo: 8) } == "P:\n\t[New Note]\n\t- a")
    }

    @Test func paste() {
        #expect(EditorSnapshot.normalizePaste("\t\ta\n\t\t\tb", baseLevel: 1) == "a\n\t\tb")
        #expect(EditorSnapshot.normalizePaste("one line", baseLevel: 3) == "one line")
    }

    @Test func visibility() {
        let text = "A\n\ta\n\t\tx\nB\n\tb" as NSString
        let idx = LineIndex(text)
        idx.setCollapsed(1, true)
        #expect(Visibility().hidden(idx) == [false, false, true, false, false])
        #expect(Visibility(focusedID: idx[1].id).hidden(idx) == [true, false, false, true, true])
        #expect(Visibility(hoistedID: idx[0].id).hidden(idx) == [true, false, true, true, true])
        let matches = ItemPath("x").evaluate(idx, text)
        let ids = Visibility.filterHiddenIDs(idx, matches: matches)
        #expect(Visibility(filterHiddenIDs: ids).hidden(idx) == [false, false, false, true, true])
    }

    @Test func idsStayUniqueAfterMovesAndUndo() {
        let text = NSMutableString(string: "A\nB\n\tb\nC\n- x\n- y")
        let idx = LineIndex(text)
        func apply(_ edit: Edit) {
            text.replaceCharacters(in: edit.range, with: edit.text)
            idx.update(text, editedRange: NSRange(location: edit.range.location, length: (edit.text as NSString).length), delta: (edit.text as NSString).length - edit.range.length)
            idx.carry(startingAt: edit.firstLine, from: edit.carry)
        }
        for (line, up) in [(3, true), (1, false), (4, true), (0, false)] {
            let snap = EditorSnapshot(text: text, index: idx, selection: NSRange(location: idx[line].start, length: 0))
            if let e = snap.moveBranches(up: up) { apply(e) }
            if let e = snap.duplicateLines() { _ = e }
        }
        let snap = EditorSnapshot(text: text, index: idx, selection: NSRange(location: idx[2].start, length: 0))
        apply(snap.duplicateLines()!)
        let ids = idx.lines.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func idsFollowContentThroughUndo() {
        let text = NSMutableString(string: "Work:\n\tP:\n\t\t- a\nHome:\n\t- h")
        let idx = LineIndex(text)
        let before = idx.lines.map(\.id)
        let original = text as String
        let snap = EditorSnapshot(text: text, index: idx, selection: NSRange(location: 0, length: 0))
        let e = snap.moveBranches(up: false)!
        let undoText = (text as NSString).substring(with: e.range)
        text.replaceCharacters(in: e.range, with: e.text)
        idx.update(text, editedRange: NSRange(location: e.range.location, length: (e.text as NSString).length), delta: (e.text as NSString).length - e.range.length)
        idx.carry(startingAt: e.firstLine, from: e.carry)
        // 실행 취소: 카리 없이 텍스트만 되돌린다
        let undoRange = NSRange(location: e.range.location, length: (e.text as NSString).length)
        text.replaceCharacters(in: undoRange, with: undoText)
        idx.update(text, editedRange: NSRange(location: e.range.location, length: (undoText as NSString).length), delta: (undoText as NSString).length - undoRange.length)
        #expect(text as String == original)
        #expect(idx.lines.map(\.id) == before)
    }

    @Test func editCarriesCollapsedState() {
        let text = NSMutableString(string: "A\nB\n\tb\nC")
        let idx = LineIndex(text)
        idx.setCollapsed(1, true)
        let snap = EditorSnapshot(text: text, index: idx, hidden: [false, false, true, false], selection: NSRange(location: 2, length: 0))
        let edit = snap.moveLines(up: true)!
        text.replaceCharacters(in: edit.range, with: edit.text)
        idx.update(text, editedRange: NSRange(location: edit.range.location, length: (edit.text as NSString).length), delta: (edit.text as NSString).length - edit.range.length)
        idx.carry(startingAt: edit.firstLine, from: edit.carry)
        #expect(text as String == "B\n\tb\nA\nC")
        #expect(idx.lines.map(\.collapsed) == [true, false, false, false])
    }
}
