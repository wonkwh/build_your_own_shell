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

## 시뮬레이터 제약

- Core ML·Vision 신경망 요청은 시뮬레이터에서 CPU 로 강제한다 (GPU 경로가 0 을 내거나 실패).
- 시뮬레이터의 `VNDetectBarcodesRequest` 는 결과를 내지 않는다. QR 은 `QRFinder` 가 대신 잡고, 바코드는 실기기에서 확인.
