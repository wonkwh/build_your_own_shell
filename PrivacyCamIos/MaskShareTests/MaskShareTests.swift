import CoreGraphics
import CoreImage
import Foundation
import AVFoundation
import CoreVideo
import ImageIO
import PDFKit
import StoreKitTest
import UIKit
import Testing
@testable import MaskShare

struct ClassifierTests {
    @Test(arguments: [
        ("mail me: kim@example.com", RedactionCategory.email),
        ("4242 4242 4242 4242", .card),
        ("CVV 123", .cardSecurityCode),
        ("CVE", .cardSecurityCode),
        ("+82 10-1234-5678", .phone),
        ("https://example.com/a", .url),
        ("221B Baker Street", .address),
        ("Hello world", .otherText),
    ])
    func classify(text: String, expected: RedactionCategory) {
        #expect(TextClassifier.classify(text) == expected)
    }

    @Test func luhn() {
        #expect(TextClassifier.passesLuhn("4242424242424242"))
        #expect(!TextClassifier.passesLuhn("4242424242424241"))
    }

    @Test func securityCodeNextToLabel() {
        let label = Detector.TextLine(text: "CVC", bounds: CGRect(x: 0, y: 0, width: 40, height: 20))
        let value = Detector.TextLine(text: "987", bounds: CGRect(x: 60, y: 0, width: 40, height: 20))
        let items = Detector.textItems([label, value], imageBounds: CGRect(x: 0, y: 0, width: 500, height: 500))
        #expect(items.map(\.category) == [.cardSecurityCode, .cardSecurityCode])
    }
}

struct PlateDecodeTests {
    /// 640x480 → scale 0.6, padY 48. 384 공간의 상자가 원본 좌표로 돌아오고 NMS 가 겹친 상자를 지운다.
    @Test func decodeMapsBackAndSuppresses() throws {
        let image = try #require(CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8, bytesPerRow: 0,
                                           space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?.makeImage())
        let lb = try #require(PlateDetector.letterbox(image))
        #expect(lb.scale == 0.6 && lb.padX == 0 && lb.padY == 48)
        // 후보 3개: 번호판(0.9), 겹치는 중복(0.8), 세로로 긴 오검출(0.95)
        let cx: [Float] = [192, 193, 100], cy: [Float] = [192, 192, 100]
        let w: [Float] = [60, 60, 10], h: [Float] = [20, 20, 40], s: [Float] = [0.9, 0.8, 0.95]
        let items = PlateDetector.decode(cx + cy + w + h + s, letterbox: lb, imageSize: CGSize(width: 640, height: 480))
        #expect(items.count == 1)
        let r = try #require(items.first).bounds
        // 원래 상자 (162,182,60,20) → (270,223.3,100,33.3) 에 가로 10%·세로 20% 여유
        #expect(abs(r.minX - 260) < 0.5 && abs(r.width - 120) < 0.5 && abs(r.minY - (223.33 - 6.67)) < 0.5)
    }

    @Test func metadataCheckFlagsGPS() throws {
        let image = try #require(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                           space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?.makeImage())
        let clean = try Renderer.encode(image, png: false)
        #expect(!Renderer.hasIdentifyingMetadata(clean))
        let dirty = NSMutableData()
        let dest = try #require(CGImageDestinationCreateWithData(dirty, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, [kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 37.5, kCGImagePropertyGPSLatitudeRef: "N"]] as CFDictionary)
        CGImageDestinationFinalize(dest)
        #expect(Renderer.hasIdentifyingMetadata(dirty as Data))
    }

    /// GPS 가 든 사진 여러 장을 내보내면 장마다 파일이 생기고 어느 것에도 메타데이터가 없다.
    @Test func exportAllStripsEveryPage() throws {
        let image = try #require(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                                           space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?.makeImage())
        let tagged = NSMutableData()
        let dest = try #require(CGImageDestinationCreateWithData(tagged, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, [kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 37.5, kCGImagePropertyGPSLatitudeRef: "N"]] as CFDictionary)
        CGImageDestinationFinalize(dest)
        #expect(Renderer.hasIdentifyingMetadata(tagged as Data))

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let box = RedactionItem(.manual, CGRect(x: 4, y: 4, width: 10, height: 10))
        let urls = try Renderer.exportAll([(.data(tagged as Data), [box]), (.image(image), [])], to: dir)
        #expect(urls.map(\.lastPathComponent) == ["MaskShare_1.jpg", "MaskShare_2.jpg"])
        for url in urls { #expect(!Renderer.hasIdentifyingMetadata(try Data(contentsOf: url))) }
    }
}

struct QRFinderTests {
    /// 실제 QR 을 흰 배경에 놓고(회전 포함) 디코딩 없이 영역을 찾는지, 빈 이미지에서는 없는지.
    @Test(arguments: [0.0, 25.0])
    func findsGeneratedQR(degrees: Double) throws {
        let qr = try #require(CIFilter(name: "CIQRCodeGenerator", parameters: ["inputMessage": Data("https://example.com/private".utf8)])?.outputImage)
            .transformed(by: .init(scaleX: 8, y: 8))
            .transformed(by: .init(rotationAngle: degrees * .pi / 180))
        let placed = qr.transformed(by: .init(translationX: 500 - qr.extent.midX, y: 400 - qr.extent.midY))
        let canvas = placed.composited(over: CIImage(color: .white)).cropped(to: CGRect(x: 0, y: 0, width: 1000, height: 800))
        let image = try #require(CIContext().createCGImage(canvas, from: canvas.extent))
        let rects = QRFinder.detect(image)
        #expect(rects.count == 1)
        let r = try #require(rects.first)
        #expect(r.contains(CGPoint(x: 500, y: 400)) && r.width > 150 && r.width < 400)

        let blank = try #require(CIContext().createCGImage(CIImage(color: .white).cropped(to: canvas.extent), from: canvas.extent))
        #expect(QRFinder.detect(blank).isEmpty)
    }
}

@MainActor
struct StoreTests {
    @Test func proUnlocksAfterPurchase() async throws {
        let session = try SKTestSession(configurationFileNamed: "MaskShare")
        session.disableDialogs = true
        session.clearTransactions()
        let store = Store()
        await store.refresh()
        #expect(!store.isPro)

        let product = try #require(try await Product.products(for: [Store.proID]).first)
        #expect(product.type == .nonConsumable)
        guard case .success(.verified(let transaction)) = try await product.purchase() else {
            Issue.record("구매 실패"); return
        }
        await transaction.finish()
        await store.refresh()
        #expect(store.isPro)

        // 환불은 비동기로 반영되므로 잠시 기다린다
        try session.refundTransaction(identifier: UInt(transaction.id))
        for _ in 0..<20 where store.isPro {
            try await Task.sleep(for: .milliseconds(100))
            await store.refresh()
        }
        #expect(!store.isPro)
    }
}

struct PDFTests {
    /// 샘플 PDF 는 무료 사용자도 열 수 있어야 한다.
    @Test func samplePDFIsFree() throws {
        let url = try #require(Bundle.main.url(forResource: SamplePicker.pdfName, withExtension: nil))
        #expect(CGPDFDocument(url as CFURL)?.numberOfPages == PDFSupport.freePageLimit)
    }

    /// 텍스트가 든 2쪽 PDF 를 가려 내보내면 쪽 크기는 그대로, 텍스트 층은 사라져야 한다.
    @Test func exportFlattensText() throws {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let data = UIGraphicsPDFRenderer(bounds: page).pdfData { ctx in
            for n in 1...2 {
                ctx.beginPage()
                ("Page \(n) kim@example.com" as NSString).draw(at: CGPoint(x: 72, y: 72), withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
            }
        }
        let picked = FileManager.default.temporaryDirectory.appendingPathComponent("Report.pdf")
        try data.write(to: picked)
        #expect(PDFDocument(url: picked)?.string?.contains("kim@example.com") == true)

        let (url, count) = try PDFSupport.importFile(picked)
        defer { [picked, url].forEach { try? FileManager.default.removeItem(at: $0) } }
        #expect(count == 2)
        let image = try PDFSupport.render(url, page: 0)
        #expect(abs(Double(image.width) / Double(image.height) - 595.0 / 842.0) < 0.01)

        let box = RedactionItem(.manual, CGRect(x: 0, y: 0, width: image.width, height: image.height / 5))
        let jobs: [(PhotoSource, [RedactionItem])] = [(.pdfPage(url, 0), [box]), (.pdfPage(url, 1), [])]
        let out = try PDFSupport.export(jobs, name: "Report", to: FileManager.default.temporaryDirectory)
        defer { try? FileManager.default.removeItem(at: out) }
        let doc = try #require(PDFDocument(url: out))
        #expect(doc.pageCount == 2)
        #expect((doc.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(doc.page(at: 0)?.bounds(for: .cropBox).size == page.size)
    }
}

struct VideoTests {
    @Test func trackInterpolatesAndHolds() throws {
        var track = VideoTrack(.face, first: Keyframe(t: 1, rect: CGRect(x: 0.1, y: 0.1, width: 0.1, height: 0.1)))
        track.keyframes.append(Keyframe(t: 2, rect: CGRect(x: 0.3, y: 0.1, width: 0.1, height: 0.1)))
        let mid = try #require(track.rect(at: 1.5))
        #expect(abs(mid.midX - 0.25) < 0.001)
        #expect(track.rect(at: 0.7) != nil)   // 첫 검출 전에도 잠시 가린다
        #expect(track.rect(at: 0.3) == nil)
        #expect(track.rect(at: 2.4) != nil)
        #expect(track.rect(at: 3) == nil)
    }

    @Test func linksMovingFaceIntoOneTrack() {
        let face = { (x: CGFloat) in (category: RedactionCategory.face, rect: CGRect(x: x, y: 0.2, width: 0.1, height: 0.1)) }
        let samples: [VideoSupport.Sample] = [
            .init(t: 0, items: [face(0.1), (.numberPlate, CGRect(x: 0.7, y: 0.7, width: 0.1, height: 0.05))]),
            .init(t: 0.3, items: [face(0.13)]),
            .init(t: 0.6, items: [face(0.16)]),
            .init(t: 3, items: [face(0.16)]),   // 오래 끊겼으니 새 트랙
        ]
        let tracks = VideoSupport.buildTracks(samples)
        #expect(tracks.filter { $0.category == .face }.map(\.keyframes.count) == [3, 1])
        #expect(tracks.filter { $0.category == .numberPlate }.count == 1)
    }

    /// 위치 정보가 든 흰 동영상의 왼쪽 절반을 가리면, 결과는 왼쪽만 검고 위치 정보가 없어야 한다.
    @Test func exportCoversTrackAndDropsLocation() async throws {
        let dir = FileManager.default.temporaryDirectory
        let src = dir.appendingPathComponent("video_src.mov")
        try await Self.makeWhiteVideo(src)
        defer { try? FileManager.default.removeItem(at: src) }
        #expect(try await VideoSupport.hasIdentifyingMetadata(src))

        var track = VideoTrack(.manual, first: Keyframe(t: 0, rect: CGRect(x: 0, y: 0, width: 0.4, height: 1)))
        track.keyframes.append(Keyframe(t: 1, rect: CGRect(x: 0, y: 0, width: 0.4, height: 1)))
        track.selected = true
        track.style = .blackout
        let out = try await VideoSupport.export(src, tracks: [track], muteAudio: true, to: dir)
        defer { try? FileManager.default.removeItem(at: out) }
        #expect(try await !VideoSupport.hasIdentifyingMetadata(out))

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: out))
        let frame = try await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image
        #expect(Self.brightness(frame, x: 0.1, y: 0.5) < 40)
        #expect(Self.brightness(frame, x: 0.9, y: 0.5) > 200)
    }

    static func makeWhiteVideo(_ url: URL) async throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let location = AVMutableMetadataItem()
        location.identifier = .quickTimeMetadataLocationISO6709
        location.value = "+37.5665+126.9780/" as NSString
        writer.metadata = [location]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 240,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 240,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for i in 0..<10 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, 320, 240, kCVPixelFormatType_32BGRA, nil, &buffer)
            let pb = try #require(buffer)
            CVPixelBufferLockBaseAddress(pb, [])
            memset(CVPixelBufferGetBaseAddress(pb), 255, CVPixelBufferGetDataSize(pb))
            CVPixelBufferUnlockBaseAddress(pb, [])
            adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 10))
        }
        input.markAsFinished()
        await writer.finishWriting()
        #expect(writer.status == .completed)
    }

    /// 0...1 좌표(좌상단 원점) 한 점의 밝기 0...255.
    static func brightness(_ image: CGImage, x: CGFloat, y: CGFloat) -> Int {
        var pixel = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.draw(image, in: CGRect(x: -x * CGFloat(image.width), y: -(1 - y) * CGFloat(image.height),
                                   width: CGFloat(image.width), height: CGFloat(image.height)))
        return (Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2])) / 3
    }
}
