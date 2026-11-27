# PlainFocusTask 설계 (1단계)

TaskPaper(`/Users/ncn/ref_source/TaskPaper`)의 기능을 외부 의존성 없는 네이티브 macOS 앱으로 다시 만든다.
TaskPaper는 웹뷰가 아니라 `NSTextView` + JavaScriptCore(birch-outline.js, birch-editor.js) 구조다. 이 JS 계층을 Swift로 옮긴다.

## 목표와 범위

- 최소 macOS 15, AppKit, Swift 6. 외부 패키지 없음. XcodeGen(`project.yml`)으로 프로젝트 생성.
- 1단계: 핵심 편집기, 질의·사이드바, 태그·날짜, 팔레트, 문서·창 기능.
- 2단계(이 문서 범위 밖): LESS 스타일시트 테마, AppleScript/JS 스크립팅, 미리 알림 가져오기·내보내기.
- 제외: 라이선스, Sparkle 업데이트, Setapp, 평가 요청, 외부 도움말 링크(앱 안 Welcome 문서로 대체).

## 성능 목표 (단위 테스트로 측정)

| 항목 | 목표 |
|---|---|
| 1만 줄 파일 열기 | 200ms 이하 |
| 입력 한 번 처리 | 1ms 이하, 문서 전체 재파싱 없음 |
| 1만 항목 질의 | 20ms 이하 |

## 구조: 텍스트가 원본

`NSTextStorage`(문서 전체 텍스트)가 유일한 원본이다. 항목 트리를 따로 두지 않는다.

```
키 입력 → NSTextStorage → LineIndex(바뀐 줄만 재파싱)
   → Styler(바뀐 줄 서식) / VisibleLines(숨길 줄 집합) / Sidebar(0.3초 디바운스) / Commands
   → NSLayoutManager: 숨긴 줄은 빈 글리프 + 높이 0
```

| 파일 | 역할 |
|---|---|
| `Model/LineIndex.swift` | 줄마다 들여쓰기 수준, 종류(project/task/note), 태그 범위·값, 부모 관계. 부분 갱신, 가지 범위 |
| `Model/ItemPath.swift` | 질의 언어 파서(재귀 하강)와 실행기 |
| `Model/DateParser.swift` | 자연어 날짜 해석·서식 |
| `Editor/OutlineTextView.swift` | `NSTextView` 하위 클래스. 손잡이(대시·점) 그리기·클릭·드래그, Tab/Shift-Tab, Return 보조, 숨은 줄 커서 보정 |
| `Editor/Folding.swift` | `NSLayoutManagerDelegate`로 줄 숨김 |
| `Editor/Styler.swift` | 종류·태그·@done·링크 서식 |
| `Editor/Commands.swift` | Item·Tag·Outline 메뉴 명령. 텍스트는 `shouldChangeText`/`didChangeText` 경로로 고쳐 실행 취소를 기록 |
| `App/Document.swift` | `NSDocument`. 텍스트 그대로 읽고 쓰기, 자동 저장·버전·탭은 시스템 |
| `App/WindowController.swift` | 사이드바(`NSOutlineView`) + 편집기 + 툴바 검색 필드 |
| `App/Palette.swift` | 무엇이든 이동·프로젝트·검색·태그·명령 팔레트(퍼지 매칭) |
| `App/DatePopover.swift`, `App/Settings.swift` | 날짜 고르기, 설정(글꼴·크기·색, 들여쓰기 폭) |

### 파일 형식 규칙 (TaskPaper와 동일)

- 들여쓰기: 탭 1개 = 1단계. 앞쪽 공백은 설정한 폭(기본 4)마다 1단계로 읽는다. 쓸 때는 원문을 바꾸지 않는다.
- 작업: `- `로 시작. 프로젝트: 끝의 태그를 뺀 내용이 `:`로 끝남. 나머지는 메모. 빈 줄은 메모.
- 태그: `(^|\s+)@이름(\(값\))?(?=\s|$)`, 값 안의 `\(` `\)`는 이스케이프. 이름 문자 집합은 `tags.coffee`를 따른다.
- 줄 끝(LF/CRLF)과 인코딩은 읽은 그대로 저장한다.

## 질의 언어 (ItemPath)

`item-path-parser.pegjs`와 `item-path.coffee`를 1:1로 옮긴다.

- 집합: `union`, `intersect`, `except`, 괄호, 슬라이스 `[n]`, `[a:b]`, 음수 인덱스.
- 경로: `/`, `//`, `..`, `.`, 축 11종. 상대 경로 첫 단계는 descendant.
- 종류: `project`, `task`, `note`.
- 논리: `and`, `or`, `not`, 괄호.
- 비교: `= != < > <= >= beginswith contains endswith matches`. 값만 쓰면 `@text contains 값`.
- 수식어: `[i]`(기본) `[s]` `[n]` `[d]` `[b]` + `[l]` 목록.
- 함수 `count(경로)`, 속성 `@text @type @id @태그`.
- 결과는 줄 번호 정렬 배열. 집합 연산은 병합 한 번.
- 파서는 키워드 위치를 함께 돌려줘 검색 필드 문법 강조에 쓴다.

편집기 필터: 일치 항목과 그 조상만 보인다. 입력 중에는 결과를 유지하고, 검색어 변경이나 새로 고침(⌘R) 때만 다시 계산한다.

## 날짜 (DateParser)

`date-time-parser.pegjs`를 옮긴다. `now today tomorrow yesterday`, `this/next/last` + 요일·월·기간 단위, `dec 25`, `2026-11-27`, `5pm`, `14:30`, `+1w -2d +3 months`. 실패하면 ISO 8601. 서식은 `YYYY-MM-DD[ HH:mm]`.

## 화면

- 창 = 문서 1개. 시스템 탭. 왼쪽 사이드바(홈, 프로젝트, 검색, 태그), 오른쪽 편집기, 툴바에 사이드바 버튼과 검색 필드.
- 사이드바 프로젝트 선택 = 포커스, 검색·태그 선택 = 필터.
- 사이드바 검색은 문서 안 `@search(...)` 항목 + 앱 지원 폴더의 전역 `searches.taskpaper`(첫 실행 때 Today, Not Done 생성). 태그 포함·제외 목록은 전역 `tags.taskpaper`.
- 접기·포커스 상태는 파일 확장 속성(xattr)에 저장한다.
- 입력 보조: 작업 줄 Return 시 `- ` 자동, 빈 작업 줄 Return 시 대시 제거, `@` 입력 시 태그 자동 완성.
- 링크(URL·이메일·경로)는 ⌘클릭으로 열고, 태그는 ⌘클릭으로 필터를 건다(일반 클릭은 편집).
- 메뉴·문구는 한국어. 새 항목 자리표시는 `- 새 작업`, `새 메모`, `새 프로젝트:`. 보관 프로젝트 이름은 TaskPaper 호환을 위해 `Archive:`.
- Hardened Runtime은 Release 빌드에만 켠다(Debug는 argent 자동화용).

## 메뉴와 단축키 (TaskPaper MainMenu.storyboard 값)

| 메뉴 | 명령 |
|---|---|
| File | 새 문서 ⌘N, 새 탭 ⌥⌘N, 열기·닫기·저장·다른 이름·되돌리기, 최근 파일, 페이지 설정, 인쇄 |
| Edit | 실행 취소·다시 실행, 표시된 항목만 복사 ⌥⌘C, 단어 ⌃W·문장 ⌃S·문단 ⇧⌘L·가지 ⇧⌘B 선택, 선택 확장·축소 ⌥⌘↑↓, 날짜 넣기, 찾기 ⌘F·바꾸기 ⌥⌘F·다음 ⌘G·이전 ⇧⌘G·선택으로 찾기 ⌘E·선택으로 이동 ⌘J, 맞춤법·대치·변환·말하기 |
| Item | 새 작업·메모·프로젝트, 그룹 ⌥⌘G, 복제 ⇧⌘D, 서식 바꾸기(프로젝트·작업·메모), 이동 ⌃⌘←→↑↓, 가지 이동 ⌃⌥⌘←→↑↓, 프로젝트로 이동 ⌘\, 항목 삭제 ⌃⇧K |
| Tag | 태그 붙이기 ⌘T, @due, @start, @today ⌘Y, @done ⌘D, 태그 지우기 ⌃⌥⌘K, @done 보관 ⇧⌘A |
| Outline | 홈 ⇧⌘H, 포커스 인·아웃 ⌥⌘→←, 펼치기·접기 ⌘0·⌘9, 완전히 ⌥⌘0·⌥⌘9, 전체 단계별 ⇧⌘0·⇧⌘9, 전체 완전히 ⇧⌥⌘0·⇧⌥⌘9 |
| View | 사이드바 ⌥⌘S, 사이드바 완전 펼치기 ⌃⌘S, 사이드바 검색 추가·편집·삭제, 편집기 검색 시작 ⇧⌘F·새로 고침 ⌘R·끝내기, 실제 크기·확대 ⌘+·축소 ⌘− |
| Palette | 무엇이든 ⌘P, 프로젝트 ⌥⌘P, 검색 ⌃⌘P, 태그, 명령 ⇧⌘P |
| Window | 전체 화면 ⌃⌘F, 항상 위에, 최소화 ⌘M, 확대, 모두 앞으로 |

## 오류 처리

| 상황 | 동작 |
|---|---|
| 인코딩을 모르는 파일 | UTF-8 → 시스템 자동 감지 순으로 시도, 실패하면 열기 오류 알림 |
| 외부에서 파일 변경 | 저장 안 한 변경이 없으면 자동으로 다시 읽음, 있으면 `NSDocument` 기본 충돌 처리 |
| 잘못된 질의 | 검색 필드를 빨간색으로 표시하고 이전 결과 유지 |
| 해석 못 하는 날짜 | `[d]` 비교 결과는 거짓, 날짜 넣기는 입력을 그대로 둠 |
| xattr 읽기·쓰기 실패 | 무시하고 모두 펼친 상태로 시작 |

## 테스트 (Swift Testing)

- `LineIndexTests`: 종류·수준·태그 파싱, 무작위 편집 뒤 부분 갱신 결과가 전체 파싱과 같은지.
- `ItemPathTests`: `birch-outline.js/test/item-path-spec.coffee`(516줄)의 사례를 옮김.
- `DateParserTests`: `date-time-parser-spec.coffee` 사례를 고정된 현재 시각으로 옮김.
- `CommandsTests`: (입력 텍스트, 선택 범위) → (결과 텍스트, 선택 범위). 이동·그룹·태그·보관·포커스 계산.
- `PerformanceTests`: 1만 줄 생성 파일로 성능 목표 3개 측정.
- 화면: 빌드 후 실제 실행해 스크린샷으로 확인.

## 구현 순서

1. 프로젝트 생성, `LineIndex`, `Styler`, `Document` (열고 저장하고 서식이 보임)
2. 접기·숨김, 손잡이, Tab 들여쓰기, 완료 토글, Return 보조
3. `Commands` (Item·Tag·Outline 메뉴)
4. `DateParser`, `ItemPath`, 편집기 검색
5. 사이드바, 포커스, 전역 검색·태그 파일, xattr 상태 저장
6. 팔레트, 날짜 팝오버, 설정, 인쇄, 표시된 항목 복사, 끌어서 놓기, 링크
7. 성능 측정과 개선
