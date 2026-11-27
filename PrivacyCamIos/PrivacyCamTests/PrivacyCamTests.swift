import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import StoreKitTest
import Testing
@testable import PrivacyCam

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
        #expect(urls.map(\.lastPathComponent) == ["PrivacyCam_safe_1.jpg", "PrivacyCam_safe_2.jpg"])
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
        let session = try SKTestSession(configurationFileNamed: "PrivacyCam")
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
