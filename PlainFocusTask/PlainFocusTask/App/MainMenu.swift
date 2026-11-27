import AppKit

/// TaskPaper MainMenu.storyboard 와 같은 구성·단축키의 메뉴.
enum MainMenu {
    private static func key(_ code: Int) -> String { String(Character(UnicodeScalar(code)!)) }
    static let up = key(NSUpArrowFunctionKey), down = key(NSDownArrowFunctionKey)
    static let left = key(NSLeftArrowFunctionKey), right = key(NSRightArrowFunctionKey)

    private static func item(_ title: String, _ action: String?, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command, tag: Int = 0) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action.map(NSSelectorFromString), keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : mods
        item.tag = tag
        return item
    }

    private static func menu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let top = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let m = NSMenu(title: title)
        items.forEach(m.addItem)
        top.submenu = m
        return top
    }

    private static var sep: NSMenuItem { .separator() }
    private static let styleSheetDelegate = StyleSheetMenuDelegate()

    static func build() -> NSMenu {
        let main = NSMenu()
        let app = "PlainFocusTask"
        let services = NSMenu(title: "서비스")
        NSApp.servicesMenu = services
        let servicesItem = NSMenuItem(title: "서비스", action: nil, keyEquivalent: "")
        servicesItem.submenu = services
        main.addItem(menu(app, [
            item("\(app)에 관하여", "orderFrontStandardAboutPanel:"), sep,
            item("설정…", "showPreferences:", ","), sep,
            servicesItem, sep,
            item("\(app) 가리기", "hide:", "h"),
            item("기타 가리기", "hideOtherApplications:", "h", [.command, .option]),
            item("모두 보기", "unhideAllApplications:"), sep,
            item("\(app) 종료", "terminate:", "q"),
        ]))

        let recent = NSMenu(title: "최근 사용")
        recent.addItem(item("메뉴 지우기", "clearRecentDocuments:"))
        recent.perform(NSSelectorFromString("_setMenuName:"), with: "NSRecentDocumentsMenu")
        let recentItem = NSMenuItem(title: "최근 사용", action: nil, keyEquivalent: "")
        recentItem.submenu = recent
        main.addItem(menu("파일", [
            item("새로 만들기", "newDocument:", "n"),
            item("새 탭", "newWindowForTab:", "n", [.command, .option]),
            item("새 윈도우", "newDocument:", "N"),
            item("열기…", "openDocument:", "o"),
            recentItem, sep,
            item("닫기", "performClose:", "w"),
            item("저장…", "saveDocument:", "s"),
            item("다른 이름으로 저장…", "saveDocumentAs:", "S"),
            item("마지막으로 저장한 버전으로 되돌리기", "revertDocumentToSaved:"), sep,
            item("미리 알림 가져오기…", "importReminders:"),
            item("미리 알림 사본 가져오기…", "importReminderCopies:"), sep,
            item("페이지 설정…", "runPageLayout:"),
            item("프린트…", "printDocument:"),
        ]))

        let find = NSTextFinder.Action.self
        main.addItem(menu("편집", [
            item("실행 취소", "undo:", "z"),
            item("실행 복귀", "redo:", "Z"), sep,
            item("오려두기", "cut:", "x"),
            item("복사하기", "copy:", "c"),
            item("보이는 항목 복사하기", "copyDisplayed:", "c", [.command, .option]),
            item("붙이기", "paste:", "v"),
            item("삭제", "delete:"),
            menu("선택", [
                item("단어 선택", "selectWord:", "w", .control),
                item("문장 선택", "selectSentence:", "s", .control),
                item("항목 선택", "selectItem:", "L"),
                item("가지 선택", "selectBranch:", "B"),
                item("선택 넓히기", "expandSelection:", up, [.command, .option]),
                item("선택 좁히기", "contractSelection:", down, [.command, .option]),
            ]),
            item("전체 선택", "selectAll:", "a"), sep,
            item("날짜 넣기…", "insertDate:"), sep,
            menu("찾기", [
                item("찾기…", "performTextFinderAction:", "f", tag: find.showFindInterface.rawValue),
                item("찾아서 바꾸기…", "performTextFinderAction:", "f", [.command, .option], tag: find.showReplaceInterface.rawValue),
                item("다음 찾기", "performTextFinderAction:", "g", tag: find.nextMatch.rawValue),
                item("이전 찾기", "performTextFinderAction:", "G", tag: find.previousMatch.rawValue),
                item("선택 항목으로 찾기", "performTextFinderAction:", "e", tag: find.setSearchString.rawValue),
                item("선택 항목으로 이동", "centerSelectionInVisibleArea:", "j"),
            ]),
            menu("맞춤법 및 문법", [
                item("맞춤법 및 문법 보기", "showGuessPanel:", ":"),
                item("지금 문서 확인", "checkSpelling:", ";"), sep,
                item("입력하는 동안 맞춤법 확인", "toggleContinuousSpellChecking:"),
                item("맞춤법과 함께 문법 확인", "toggleGrammarChecking:"),
                item("자동으로 맞춤법 수정", "toggleAutomaticSpellingCorrection:"),
            ]),
            menu("대치", [
                item("대치 보기", "orderFrontSubstitutionsPanel:"), sep,
                item("스마트 복사하기/붙이기", "toggleSmartInsertDelete:"),
                item("스마트 인용", "toggleAutomaticQuoteSubstitution:"),
                item("스마트 대시", "toggleAutomaticDashSubstitution:"),
                item("스마트 링크", "toggleAutomaticLinkDetection:"),
                item("데이터 감지기", "toggleAutomaticDataDetection:"),
                item("텍스트 대치", "toggleAutomaticTextReplacement:"),
            ]),
            menu("변형", [
                item("대문자로 만들기", "uppercaseWord:"),
                item("소문자로 만들기", "lowercaseWord:"),
                item("단어의 첫 문자를 대문자로", "capitalizeWord:"),
            ]),
            menu("말하기", [
                item("말하기 시작", "startSpeaking:"),
                item("말하기 중단", "stopSpeaking:"),
            ]),
        ]))

        main.addItem(menu("항목", [
            item("새 작업", "newTask:", "\r"),
            item("새 메모", "newNote:", "\r", [.command, .option]),
            item("새 프로젝트", "newProject:", "\r", [.command, .shift]), sep,
            item("묶기", "groupLines:", "g", [.command, .option]),
            item("복제", "duplicateLines:", "D"),
            menu("서식", [
                item("프로젝트", "formatProject:"),
                item("작업", "formatTask:"),
                item("메모", "formatNote:"),
            ]), sep,
            item("오른쪽으로", "moveLineRight:", right, [.command, .control]),
            item("가지 오른쪽으로", "moveBranchesRight:", right, [.command, .control, .option]),
            item("왼쪽으로", "moveLineLeft:", left, [.command, .control]),
            item("가지 왼쪽으로", "moveBranchesLeft:", left, [.command, .control, .option]),
            item("위로", "moveLineUp:", up, [.command, .control]),
            item("가지 위로", "moveBranchesUp:", up, [.command, .control, .option]),
            item("아래로", "moveLineDown:", down, [.command, .control]),
            item("가지 아래로", "moveBranchesDown:", down, [.command, .control, .option]), sep,
            item("프로젝트로 옮기기…", "moveToProject:", "\\"), sep,
            item("미리 알림으로 내보내기…", "exportToReminders:"),
            item("미리 알림으로 사본 내보내기…", "exportCopyToReminders:"), sep,
            item("항목 삭제", "deleteLines:", "K", .control),
        ]))

        main.addItem(menu("태그", [
            item("태그 붙이기…", "tagWith:", "t"), sep,
            item("마감일 @due", "toggleDue:"),
            item("시작일 @start", "toggleStart:"),
            item("오늘 @today", "toggleToday:", "y"),
            item("완료 @done", "toggleDone:", "d"), sep,
            item("태그 지우기", "clearTags:", "k", [.command, .control, .option]),
            item("@done 항목 보관", "archiveDone:", "A"),
        ]))

        main.addItem(menu("개요", [
            item("홈으로", "goHome:", "H"),
            item("포커스 인", "focusIn:", right, [.command, .option]),
            item("포커스 아웃", "focusOut:", left, [.command, .option]), sep,
            item("펼치기", "expandItems:", "0"),
            item("완전히 펼치기", "expandItemsCompletely:", "0", [.command, .option]),
            item("접기", "collapseItems:", "9"),
            item("완전히 접기", "collapseItemsCompletely:", "9", [.command, .option]), sep,
            item("모두 한 단계 펼치기", "increaseExpansionLevel:", "0", [.command, .shift]),
            item("모두 완전히 펼치기", "expandAll:", "0", [.command, .shift, .option]),
            item("모두 한 단계 접기", "decreaseExpansionLevel:", "9", [.command, .shift]),
            item("모두 완전히 접기", "collapseAll:", "9", [.command, .shift, .option]),
        ]))

        main.addItem(menu("보기", [
            item("사이드바 보기", "toggleSidebar:", "s", [.command, .option]),
            item("사이드바 보기 및 모두 펼치기", "showSidebarAndExpandCompletely:", "s", [.command, .control]), sep,
            item("새 사이드바 검색…", "newSidebarSearch:"),
            item("사이드바 검색 편집…", "editSidebarSearch:"),
            item("사이드바 검색 삭제", "deleteSidebarSearch:"), sep,
            item("편집기 검색 시작", "beginSearch:", "F"),
            item("편집기 검색 새로 고침", "refreshSearch:", "r"),
            item("편집기 검색 끝내기", "closeSearch:"), sep,
            item("실제 크기", "zoomToActualSize:"),
            item("확대", "zoomIn:", "+"),
            item("축소", "zoomOut:", "-"),
        ]))

        main.addItem(menu("팔레트", [
            item("무엇이든 이동…", "showGoToPalette:", "p"),
            item("프로젝트로 이동…", "showProjectsPalette:", "p", [.command, .option]),
            item("검색으로 이동…", "showSearchesPalette:", "p", [.command, .control]),
            item("태그로 이동…", "showTagsPalette:"),
            item("명령…", "showCommandsPalette:", "P"),
        ]))

        let styleSheet = NSMenuItem(title: "스타일시트", action: nil, keyEquivalent: "")
        styleSheet.submenu = NSMenu(title: "스타일시트")
        styleSheet.submenu?.delegate = styleSheetDelegate
        let window = menu("윈도우", [
            styleSheet, sep,
            item("전체 화면 시작", "toggleFullScreen:", "f", [.command, .control]),
            item("항상 위에 띄우기", "toggleFloating:"),
            item("최소화", "performMiniaturize:", "m"),
            item("확대/축소", "performZoom:"), sep,
            item("모두 앞으로 가져오기", "arrangeInFront:"),
        ])
        NSApp.windowsMenu = window.submenu
        main.addItem(window)

        let help = menu("도움말", [
            item("PlainFocusTask 안내 문서", "openWelcome:", "?"),
            item("TaskPaper 사용 설명서 (웹)", "openUsersGuide:"),
        ])
        NSApp.helpMenu = help.submenu
        main.addItem(help)
        return main
    }
}
