# PrivacyCam iOS

Flutter PrivacyCam 의 사진 기능을 SwiftUI 로 옮긴 iOS 전용 앱. 모든 검출은 기기 안에서 돈다.

| 대상 | 원본 (Flutter) | iOS |
|---|---|---|
| 얼굴 | ML Kit | `VNDetectFaceRectanglesRequest` |
| 사람 | YOLOX-nano ONNX | `VNDetectHumanRectanglesRequest` (모델 파일 없음) |
| 텍스트 | ML Kit (Latin) | `VNRecognizeTextRequest` (ko, en) + 같은 정규식 분류 |
| QR·바코드 | ML Kit | `VNDetectBarcodesRequest` + 읽히지 않는 QR 은 finder 패턴 검출(`QRFinder`) |
| 번호판 | YOLOv9-t ONNX (NMS 포함) | Core ML FP16, NMS 는 Swift |

## 실행

```sh
xcodegen generate
open PrivacyCam.xcodeproj
```

## 번호판 모델

`PrivacyCam/Models/LicensePlateDetector.mlpackage` 는 open-image-models 의
`yolo-v9-t-384-license-plate-end2end` 를 `/model/model.22/Concat_5` 에서 잘라 NMS 를 뺀 뒤 변환했다.
다시 만들려면 `tools/convert_plate_model.py`. 라이선스는 `PrivacyCam/Models/OPEN_IMAGE_MODELS_MIT_LICENSE.txt`.

## 샘플 사진

`showcase_N_1` 은 Wikimedia Commons 의 CC0 사진이고, `showcase_N_2` 는 이 앱의 검출기·렌더러로 기본 설정 그대로 만든 보호본이다.

| N | 보여 주는 것 | 원본 | 작성자 | 라이선스 |
|---|---|---|---|---|
| 1 | 번호판 | [Mercedes C-Class Slovenia plate (50917990426).jpg](https://commons.wikimedia.org/wiki/File:Mercedes_C-Class_Slovenia_plate_(50917990426).jpg) | crash71100 | CC0 |
| 2 | QR 코드 | [QR code signs (52900681507).jpg](https://commons.wikimedia.org/wiki/File:QR_code_signs_(52900681507).jpg) | Khronos-dolls from Hakata-ku Fukuoka-shi | CC0 |
| 3 | 개인정보 텍스트 (가운데 열만 잘라 씀) | [Digital Business Card Example.png](https://commons.wikimedia.org/wiki/File:Digital_Business_Card_Example.png) | DoubleCritch | CC0 |
| 4 | 얼굴 | [Three friends by train tracks (Unsplash).jpg](https://commons.wikimedia.org/wiki/File:Three_friends_by_train_tracks_(Unsplash).jpg) | Priscilla Du Preez artographybyp | CC0 |

## PDF

쪽마다 이미지로 그려 같은 검출기로 검사하고, 가린 이미지만으로 새 PDF 를 만든다. 원본의 텍스트 층·링크·메타데이터는 옮기지 않으며, 내보낸 파일에 선택 가능한 텍스트가 남으면 내보내기를 멈춘다. 암호가 걸린 PDF 는 받지 않는다.

## 인앱 결제

무료는 사진 한 장씩과 2쪽까지의 PDF, Pro(비소모성 `com.wonkwh.privacycam.pro`, $4.99) 는 사진 최대 10장과 PDF 50쪽까지 처리한다.
App Store Connect 에 같은 ID 로 상품을 만들어야 실기기에서 보인다. 로컬 테스트는 `PrivacyCam.storekit` (Xcode Run, `StoreTests`).

## 시뮬레이터 제약

- Core ML·Vision 신경망 요청은 시뮬레이터에서 CPU 로 강제한다 (GPU 경로가 0 을 내거나 실패).
- 시뮬레이터의 `VNDetectBarcodesRequest` 는 결과를 내지 않는다. QR 은 `QRFinder` 가 대신 잡고, 바코드는 실기기에서 확인.
