# Todo: 영상 링크 (YouTube · mp4)

운동·할일 루틴에 YouTube 영상이나 mp4 같은 영상 파일 링크를 붙여 실행 화면에서 같이 본다.

## 정할 것

| 결정 | 선택지 | 추천 |
|---|---|---|
| 링크 단위 | 루틴마다 1개 / 세트·구간마다 | 루틴마다 1개. 세트마다 다는 건 나중에 필드를 늘려 붙인다 |
| 재생 방식 | 앱 안에서 재생 / YouTube 앱으로 열기만 | 앱 안에서 재생. 재생이 막힌 영상은 YouTube 앱으로 연다. 영상 파일은 AVPlayer |
| 타이머와 영상 | 따로 움직임 / 일시정지를 같이 | 처음엔 따로. 같이 묶는 건 3단계 뒤 |
| 할일 | 별도 모델 / 루틴 하나로 | 루틴 하나로. 할일은 세트 1, 휴식 0인 루틴 |

## 1단계: 데이터

- [x] `Routine` 모델: 이름, 세트·운동·휴식, 영상 URL(선택). SwiftData 로 저장. YouTube 시작 시각은 따로 두지 않고 링크의 `t=` 를 쓴다
- [x] 지금 `@AppStorage` 에 있는 `sets`·`work`·`rest` 를 첫 루틴으로 옮기기
- [x] 영상 링크 파서(`VideoSource`)와 테스트
  - YouTube: `youtu.be/ID`, `watch?v=`, `/shorts/`, `/live/`, `/embed/`, `m.`·`music.` 도메인, `t=`·`start=` 시작 시각, 영상 ID 11자 확인
  - 영상 파일: https 이고 확장자가 `mp4`·`m4v`·`mov`·`m3u8`. http 는 ATS 가 막아 받지 않는다

## 2단계: 화면

- [x] 루틴 목록을 새 홈으로. 행에는 썸네일, 이름, 총 시간. + 로 추가, 밀어서 삭제
- [x] 설정 화면에 이름 행, 영상 링크 행 추가. `PasteButton` 으로 붙여넣기 권한 창 없이 붙여넣기
- [x] 링크를 넣으면 제목·썸네일 미리보기 (YouTube). 영상 파일은 `AVAssetImageGenerator` 로 첫 프레임. 이름이 "새 루틴" 이면 영상 제목으로 바꾼다
  - oEmbed (`https://www.youtube.com/oembed?url=<URL>&format=json`), API 키 필요 없음
  - 썸네일 `https://i.ytimg.com/vi/<ID>/hqdefault.jpg`
- [x] 실행 화면: 위에 16:9 영상 자리, 아래로 작은 링, −10초 / +10초, 일시정지. 지금은 썸네일을 누르면 YouTube 앱·사파리로 연다 (3단계에서 앱 안 플레이어로)

## 3단계: 플레이어

- [ ] `WKWebView` + YouTube IFrame Player API, 화면 안 재생(`playsinline`)
- [ ] JS → 앱으로 재생 상태·오류 전달
- [ ] 오류 101·150(퍼가기 막힘), 오프라인, 로딩 실패면 "YouTube에서 열기" 버튼
- [ ] 쿠키를 줄이려면 `youtube-nocookie.com` 검토
- [ ] 영상 파일: AVKit `VideoPlayer`, 로딩 실패·오프라인이면 오류 문구

## 4단계: 나중에

- [ ] 공유 확장: YouTube 앱에서 공유하면 바로 루틴 추가 (새 타깃 + App Group)
- [ ] 영상 재생·일시정지와 타이머 동기화
- [ ] 구간 전환 소리, 종료 직전 3초 카운트 소리
- [ ] 백그라운드에서 구간이 바뀌면 알림
- [ ] 다크 모드 화면 확인

## 출시 전 확인

- [ ] YouTube API 개발자 정책 원문 확인: 플레이어 가리기·소리만 재생·백그라운드 재생 금지, 플레이어 최소 크기 200×200
- [ ] App Store 개인정보 라벨에 앱 안 재생 시 YouTube 쿠키·추적 반영
- [ ] 앱 이름의 "Tube" 가 YouTube 브랜드 가이드에 걸리는지
