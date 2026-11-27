import AppKit
import Testing

@Suite struct ThemeTests {
    @Test func parsesVariablesRulesAndColorFunctions() {
        let less = """
        // 주석
        @text-color: #112233;
        @bg: #ffffff;
        @background-color: @bg;
        @tint-color: mix(#000000, #ffffff, 50%);
        editor { line-height-multiple: 1.5; font-family: "Menlo"; }
        item[data-type=project] { font-weight: bold; color: red; }
        item[data-today] { background-color: fade(#ff0000, 30%); }
        run[tag=data-due] { color: #00ff00; }
        run[tag] { color: rgb(10, 20, 30); }
        item[data-done] > run[content] { text-decoration: line-through; }
        """
        let t = Theme.parse(less, name: "t", dark: false)
        #expect(t.lineHeight == 1.5)
        #expect(t.fontFamily == "Menlo")
        #expect(t.text?.usingColorSpace(.sRGB)?.redComponent == CGFloat(0x11) / 255)
        #expect(t.background?.usingColorSpace(.sRGB)?.greenComponent == 1)
        #expect(abs((t.tint?.usingColorSpace(.sRGB)?.redComponent ?? 0) - 0.5) < 0.01)
        #expect(t.style(.type(.project))?.bold == true)
        #expect(t.style(.itemTag("today"))?.background?.alphaComponent ?? 0 > 0.29)
        #expect(t.style(.tag("due"))?.color != nil)
        #expect(t.style(.anyTag)?.color != nil)
        #expect(t.style(.itemTag("done"))?.strike == true)
    }
}
