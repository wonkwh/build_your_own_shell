import CoreGraphics
import CoreML
import Vision

/// 온디바이스 검출. 얼굴·사람·텍스트·바코드는 Vision, 번호판은 변환한 Core ML 모델.
enum Detector {
    static func detect(_ image: CGImage) async -> [RedactionItem] {
        let size = CGSize(width: image.width, height: image.height)
        async let vision = visionItems(image, size: size)
        async let plates = (try? PlateDetector.detect(image)) ?? []
        async let finderQRs = QRFinder.detect(image)
        var items = await vision + plates
        // Vision 이 읽은 QR 과 겹치지 않는, 읽히지 않는 QR 모양만 더한다.
        let bounds = CGRect(origin: .zero, size: size)
        for r in await finderQRs where !items.contains(where: { $0.category == .qrCode && r.contains(CGPoint(x: $0.bounds.midX, y: $0.bounds.midY)) }) {
            items.append(RedactionItem(.qrCode, r.intersection(bounds)))
        }
        return items
    }

    // MARK: Vision

    private static func visionItems(_ image: CGImage, size: CGSize) -> [RedactionItem] {
        let faces = VNDetectFaceRectanglesRequest()
        let humans = VNDetectHumanRectanglesRequest()
        humans.upperBodyOnly = false
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .accurate
        text.usesLanguageCorrection = false
        text.recognitionLanguages = ["ko-KR", "en-US"]
        let codes = VNDetectBarcodesRequest()

        // 한 요청이 실패해도 나머지는 돌도록 따로 실행한다. 실패한 요청은 results 가 nil.
        let handler = VNImageRequestHandler(cgImage: image)
        for request in [faces, humans, text, codes] as [VNRequest] {
            #if targetEnvironment(simulator)
            // 시뮬레이터는 Vision 신경망 요청이 "Could not create inference context" 로 실패한다.
            if let cpu = MLComputeDevice.allComputeDevices.first(where: { if case .cpu = $0 { true } else { false } }) {
                request.setComputeDevice(cpu, for: .main)
            }
            #endif
            try? handler.perform([request])
        }

        let bounds = CGRect(origin: .zero, size: size)
        func rect(_ o: VNDetectedObjectObservation) -> CGRect {
            let r = VNImageRectForNormalizedRect(o.boundingBox, Int(size.width), Int(size.height))
            return CGRect(x: r.minX, y: size.height - r.maxY, width: r.width, height: r.height).intersection(bounds)
        }

        var items: [RedactionItem] = []
        for o in faces.results ?? [] {
            items.append(.init(.face, rect(o).padded(left: 0.24, top: 0.3, right: 0.24, bottom: 0.3, in: bounds)))
        }
        for o in humans.results ?? [] {
            let r = rect(o)
            guard r.width >= 12, r.height >= 18 else { continue }
            // 머리카락·손·옷자락까지 덮는 여유.
            items.append(.init(.person, r.padded(left: 0.09, top: 0.08, right: 0.09, bottom: 0.05, in: bounds), confidence: o.confidence))
        }
        for o in codes.results ?? [] {
            let isQR = o.symbology == .qr || o.symbology == .microQR
            items.append(.init(isQR ? .qrCode : .barcode, rect(o)))
        }
        let lines = (text.results ?? []).compactMap { o in
            o.topCandidates(1).first.map { TextLine(text: $0.string, bounds: rect(o)) }
        }
        items += textItems(lines, imageBounds: bounds)
        return items
    }

    // MARK: 텍스트 문맥 분류

    struct TextLine { let text: String; let bounds: CGRect }

    static func textItems(_ lines: [TextLine], imageBounds: CGRect) -> [RedactionItem] {
        lines.map { line in
            let category = category(of: line, in: lines)
            var r = line.bounds
            if category == .cardSecurityCode {
                let h = max(r.width * 0.06, r.height * 0.65), v = r.height * 0.35
                r = r.insetBy(dx: -h, dy: -v).intersection(imageBounds)
            }
            return RedactionItem(category, r, label: line.text)
        }
    }

    private static func category(of line: TextLine, in lines: [TextLine]) -> RedactionCategory {
        let direct = TextClassifier.classify(line.text)
        if direct != .otherText { return direct }
        if isInAddressBlock(line, lines) { return .address }
        guard TextClassifier.hasPossibleSecurityCode(line.text) else { return direct }
        let nearLabel = lines.contains {
            (TextClassifier.isSecurityCodeLabel($0.text) || TextClassifier.isSecurityContext($0.text))
                && near($0.bounds, line.bounds, maxH: max($0.bounds.width * 1.5, height($0, line) * 8), maxV: height($0, line) * 2.5)
        }
        let nearCard = lines.contains {
            TextClassifier.classify($0.text) == .card
                && near($0.bounds, line.bounds, maxH: max($0.bounds.width * 0.6, height($0, line) * 10), maxV: height($0, line) * 10)
        }
        return nearLabel || nearCard ? .cardSecurityCode : .otherText
    }

    /// 주소 라벨/주소 값 바로 아래, 왼쪽 정렬된 줄은 주소 블록으로 본다.
    private static func isInAddressBlock(_ line: TextLine, _ lines: [TextLine]) -> Bool {
        lines.contains { anchor in
            guard TextClassifier.isAddressLabel(anchor.text) || TextClassifier.looksLikeAddress(anchor.text) else { return false }
            let h = height(anchor, line)
            return line.bounds.minY >= anchor.bounds.minY - h * 0.4
                && line.bounds.minY <= anchor.bounds.maxY + h * 4
                && abs(anchor.bounds.minX - line.bounds.minX) <= h * 2.2
        }
    }

    private static func height(_ a: TextLine, _ b: TextLine) -> CGFloat { max(a.bounds.height, b.bounds.height) }

    private static func near(_ a: CGRect, _ b: CGRect, maxH: CGFloat, maxV: CGFloat) -> Bool {
        max(0, max(a.minX, b.minX) - min(a.maxX, b.maxX)) <= maxH
            && max(0, max(a.minY, b.minY) - min(a.maxY, b.maxY)) <= maxV
    }
}

// MARK: - 번호판 (YOLOv9-t 384, NMS 는 여기서)

enum PlateDetector {
    static let inputSize = 384

    nonisolated(unsafe) private static let model: MLModel? = {
        guard let url = Bundle.main.url(forResource: "LicensePlateDetector", withExtension: "mlmodelc") else { return nil }
        let config = MLModelConfiguration()
        #if targetEnvironment(simulator)
        config.computeUnits = .cpuOnly // 시뮬레이터 GPU 경로는 이 FP16 모델 출력이 전부 0.
        #endif
        return try? MLModel(contentsOf: url, configuration: config)
    }()

    static func detect(_ image: CGImage) throws -> [RedactionItem] {
        guard let model,
              let constraint = model.modelDescription.inputDescriptionsByName["images"]?.imageConstraint,
              let letterbox = letterbox(image) else { return [] }
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "images": MLFeatureValue(cgImage: letterbox.image, constraint: constraint),
        ])
        guard let raw = try model.prediction(from: input).featureValue(for: "predictions")?.multiArrayValue else { return [] }
        return decode(MLShapedArray<Float>(converting: raw).scalars, letterbox: letterbox,
                      imageSize: CGSize(width: image.width, height: image.height))
    }

    struct Letterbox { let image: CGImage; let scale: CGFloat; let padX: CGFloat; let padY: CGFloat }

    /// 학습 전처리와 같게 비율 유지 축소 후 114 회색 정사각형 가운데에 놓는다.
    static func letterbox(_ image: CGImage) -> Letterbox? {
        let s = CGFloat(inputSize)
        let scale = min(s / CGFloat(image.width), s / CGFloat(image.height))
        let w = max(1, (CGFloat(image.width) * scale).rounded()), h = max(1, (CGFloat(image.height) * scale).rounded())
        let padX = (s - w) / 2, padY = (s - h) / 2
        guard let ctx = CGContext(data: nil, width: inputSize, height: inputSize, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(red: 114 / 255, green: 114 / 255, blue: 114 / 255, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
        ctx.interpolationQuality = .high
        let left = (padX - 0.1).rounded(), top = (padY - 0.1).rounded()
        ctx.draw(image, in: CGRect(x: left, y: s - top - h, width: w, height: h))
        return ctx.makeImage().map { Letterbox(image: $0, scale: scale, padX: padX, padY: padY) }
    }

    /// `p` 는 [5, N] 평탄화 값(cx, cy, w, h, score).
    static func decode(_ p: [Float], letterbox: Letterbox, imageSize: CGSize, threshold: Float = 0.4) -> [RedactionItem] {
        let n = p.count / 5, s = CGFloat(inputSize)
        let bounds = CGRect(origin: .zero, size: imageSize)
        var candidates: [(CGRect, Float)] = []
        for i in 0..<n where p[4 * n + i] >= threshold && p[4 * n + i] <= 1.001 {
            let w = CGFloat(p[2 * n + i]), h = CGFloat(p[3 * n + i])
            // 번호판은 가로로 길다. 세로 텍스트 조각 같은 오검출을 거른다.
            guard w >= 6, h >= 3, (1.1...8).contains(w / h), w * h <= s * s * 0.35 else { continue }
            let x = CGFloat(p[i]) - w / 2, y = CGFloat(p[n + i]) - h / 2
            let r = CGRect(x: (x - letterbox.padX) / letterbox.scale, y: (y - letterbox.padY) / letterbox.scale,
                           width: w / letterbox.scale, height: h / letterbox.scale).intersection(bounds)
            guard !r.isNull, r.width >= 4, r.height >= 3 else { continue }
            candidates.append((r.padded(left: 0.1, top: 0.2, right: 0.1, bottom: 0.2, in: bounds), p[4 * n + i]))
        }
        var kept: [(CGRect, Float)] = []
        for c in candidates.sorted(by: { $0.1 > $1.1 }) where !kept.contains(where: { $0.0.iou(c.0) > 0.45 }) {
            kept.append(c)
            // 384 입력으로는 많은 번호판을 구분할 수 없다. 이상 출력이 사진 전체를 덮는 것보다 상한이 안전하다.
            if kept.count == 20 { break }
        }
        return kept.map { RedactionItem(.numberPlate, $0.0, confidence: $0.1) }
    }
}
