# PlainFocusTask 1단계 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. 체크박스(`- [x]`)로 진행을 기록한다.

**Goal:** TaskPaper 1단계 기능(A–E)을 외부 의존성 없는 AppKit 앱으로 구현한다.

**Architecture:** `NSTextStorage`가 원본. `LineIndex`가 줄 단위 구조(종류·태그·부모·가지)를 부분 갱신하고, 명령은 줄 구간을 새 줄 목록으로 바꾸는 순수 함수(`Commands`)로 계산해 `NSTextView` 편집 API로 한 번에 적용한다. 숨김(접기·포커스·필터)은 `NSLayoutManagerDelegate`가 처리한다.

**Tech Stack:** Swift 6, AppKit(TextKit 1), Foundation, Swift Testing, XcodeGen.

## Global Constraints

- 최소 macOS 15.0, 외부 패키지 없음
- 번들 ID `com.wonkwh.PlainFocusTask`, 팀 `AEVQL949E2`
- 파일 형식은 TaskPaper와 같다(탭 들여쓰기, `- ` 작업, `:` 프로젝트, `@tag(value)`)
- 성능: 1만 줄 열기 200ms, 입력 1ms, 질의 20ms 이하
- 주석은 1~2줄, 함수 헤더는 DocC 스타일
- 커밋은 사용자가 지시할 때만

## 파일 구조

| 파일 | 책임 |
|---|---|
| `project.yml` | 앱 + 테스트 타깃. 테스트 타깃은 `PlainFocusTask/Model`을 직접 컴파일(호스트 앱 없음) |
| `PlainFocusTask/Model/LineIndex.swift` | 줄 파싱·부분 갱신·트리 구조 |
| `PlainFocusTask/Model/DateParser.swift` | 자연어 날짜 해석·서식 |
| `PlainFocusTask/Model/ItemPath.swift` | 질의 파서·실행기 |
| `PlainFocusTask/Model/Commands.swift` | 텍스트 편집 명령(순수 함수) → `Edit` |
| `PlainFocusTask/Model/Visibility.swift` | 접기·포커스·필터 → 숨김 배열 |
| `PlainFocusTask/Editor/*` | 텍스트 뷰, 서식, 숨김 레이아웃, 편집기 컨트롤러 |
| `PlainFocusTask/App/*` | 문서, 창, 사이드바, 팔레트, 날짜, 설정, 메뉴, 전역 설정 파일 |

## 핵심 인터페이스

```swift
enum ItemType: String { case project, task, note }
struct Tag { var name: String; var value: String?; var range: NSRange /* 줄 시작 기준, 앞 공백 제외 */; var fullRange: NSRange /* 앞 공백 포함 */ }
struct Line { var id: Int; var start: Int; var length: Int; var terminator: Int; var indentLength: Int; var level: Int
  var type: ItemType; var tags: [Tag]; var contentEnd: Int; var parent: Int; var branchEnd: Int; var collapsed: Bool }
final class LineIndex { init(_ text: NSString); func update(_ text: NSString, editedRange: NSRange, delta: Int)
  func line(at location: Int) -> Int; var lines: [Line] }
enum DateParser { static func parse(_ s: String, now: Date = .now) -> Date?; static func format(_ d: Date) -> String }
struct ItemPath { init(_ source: String); var error: String?; func evaluate(_ index: LineIndex, _ text: NSString, now: Date = .now) -> [Int] }
struct Edit { var range: NSRange; var text: String; var selection: NSRange; var carry: [Int?] }
```

## 작업

### Task 1: 프로젝트와 LineIndex
- [x] `project.yml`, 빈 앱 진입점, 테스트 타깃 생성 → `xcodegen generate`
- [x] `LineIndexTests`: 종류(`- a` task, `P:` project, `P: @t` project, `P: ` note), 태그 값·이스케이프, 레벨(탭, 공백 4칸), 빈 줄 깊이, 부모·가지 끝
- [x] 무작위 편집 1000회 후 부분 갱신 결과 == 전체 파싱 결과 테스트
- [x] 구현 후 `xcodebuild test` 통과

### Task 2: DateParser
- [x] `date-time-parser-spec.coffee` 사례를 고정 시각으로 옮긴 테스트 작성 → 실패 확인
- [x] 구현 → 통과

### Task 3: ItemPath
- [x] `item-path-spec.coffee` 사례를 옮긴 테스트(축, 종류, 논리, 관계, 수식어, 집합, 슬라이스, count) → 실패 확인
- [x] 파서(PEG 선택 순서 그대로) + 실행기 → 통과

### Task 4: Commands + Visibility
- [x] 테스트: 들여쓰기/내어쓰기(접힌 자손 동반), 줄·가지 위·아래 이동, 그룹, 복제, 항목 삭제, 서식 바꾸기, 태그 토글·지우기, @done 보관(@project 태그), 프로젝트로 이동, Return 분할 규칙, 줄 시작 Backspace, 접기·포커스·필터 숨김 계산
- [x] 구현 → 통과

### Task 5: 편집기
- [x] TextKit 1 스택, `Styler`(프로젝트 굵게, 메모 기울임, 태그 흐림, @done 취소선, 링크 색), 손잡이 그리기·클릭(접기), 대시 클릭(@done), 숨김 레이아웃, 커서 보정, Tab/Shift-Tab/Return/Backspace, 붙여넣기 들여쓰기 정리, ⌘클릭 링크·태그 필터
- [x] 앱 실행 후 스크린샷으로 확인

### Task 6: 문서·창·메뉴
- [x] `NSDocument`(텍스트 그대로, xattr에 접기·포커스 저장), 창(사이드바+편집기+검색 필드), 탭, 전체 메뉴·단축키, 확대·축소, 항상 위에, 인쇄, 표시된 항목 복사

### Task 7: 사이드바·검색·팔레트·날짜·설정
- [x] 사이드바(홈·프로젝트·검색·태그와 값), 사이드바 검색 추가·편집·삭제, 전역 `searches.taskpaper`/`tags.taskpaper`
- [x] 편집기 검색(⇧⌘F, ⌘R 새로 고침, 잘못된 질의 빨간 표시)
- [x] 팔레트(무엇이든·프로젝트·검색·태그·명령), 프로젝트로 이동, 태그 붙이기
- [x] 날짜 팝오버(@due, @start, 날짜 넣기), 설정 창, Welcome 문서

### Task 8: 성능
- [x] `PerformanceTests`: 1만 줄 파싱, 한 글자 부분 갱신, 질의 3종 시간 측정
- [x] 실제 앱에서 1만 줄 문서 열기·입력 확인
