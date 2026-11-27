import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageError: LocalizedError {
    case unsupported, tooLarge, renderFailed, metadataNotRemoved

    var errorDescription: String? {
        switch self {
        case .unsupported: "이미지가 손상되었거나 지원하지 않는 형식입니다."
        case .tooLarge: "이미지가 너무 커서 이 기기에서 안전하게 처리할 수 없습니다."
        case .renderFailed: "보호된 사본을 만들지 못했습니다."
        case .metadataNotRemoved: "메타데이터 제거를 확인하지 못해 내보내기를 중단했습니다."
        }
    }
}

/// 원본 데이터, 샘플 이미지, PDF 한 쪽. 쓸 때마다 디코드해 여러 장을 메모리에 쌓지 않는다.
enum PhotoSource: Sendable {
    case data(Data), image(CGImage), pdfPage(URL, Int)

    func load() throws -> (image: CGImage, isPNG: Bool) {
        switch self {
        case .data(let data): try Renderer.load(data)
        case .image(let image): (image, false)
        case .pdfPage(let url, let index): (try PDFSupport.render(url, page: index), false)
        }
    }
}

enum Renderer {
    static let maxPixels = 60_000_000
    static let blurStrength: CGFloat = 18
    static let pixelSize: CGFloat = 14
    private static let context = CIContext()

    /// 원본을 디코드하면서 EXIF 방향을 픽셀에 굽는다. 결과 CGImage 에는 메타데이터가 없다.
    static func load(_ data: Data) throws -> (image: CGImage, isPNG: Bool) {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int
        else { throw ImageError.unsupported }
        guard w * h <= maxPixels else { throw ImageError.tooLarge }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(w, h),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { throw ImageError.unsupported }
        return (image, CGImageSourceGetType(src) as String? == UTType.png.identifier)
    }

    static func render(_ image: CGImage, items: [RedactionItem]) throws -> CGImage {
        let source = CIImage(cgImage: image)
        var out = source
        for item in items where item.selected {
            // Core Image 는 좌하단 원점.
            let r = CGRect(x: item.bounds.minX, y: CGFloat(image.height) - item.bounds.maxY,
                           width: item.bounds.width, height: item.bounds.height).integral.intersection(source.extent)
            guard !r.isNull, r.width >= 1, r.height >= 1 else { continue }
            let region = out.cropped(to: r).clampedToExtent()
            let patch: CIImage = switch item.style {
            case .blackout:
                CIImage(color: .black)
            case .blur:
                // 얼굴은 크기에 비례해 더 강하게 흐린다.
                region.applyingGaussianBlur(sigma: item.category == .face ? max(blurStrength, min(r.width, r.height) * 0.15) : blurStrength)
            case .pixelate:
                region.applyingFilter("CIPixellate", parameters: [
                    kCIInputScaleKey: pixelBlock(item.category, r),
                    kCIInputCenterKey: CIVector(cgPoint: r.origin),
                ])
            }
            out = patch.cropped(to: r).composited(over: out)
        }
        guard let cg = context.createCGImage(out, from: source.extent) else { throw ImageError.renderFailed }
        return cg
    }

    /// QR 모듈·번호판 글자가 작은 블록을 견디므로 카테고리별 최소 블록을 강제한다.
    static func pixelBlock(_ category: RedactionCategory, _ r: CGRect) -> CGFloat {
        let side = min(r.width, r.height)
        let minimum: CGFloat = switch category {
        case .qrCode: min(max((side / 12).rounded(.up), 12), 160)
        case .numberPlate: min(max((side / 5).rounded(.up), 10), 160)
        case .person: min(max((side / 20).rounded(.up), 10), 160)
        default: 4
        }
        return max(pixelSize, minimum)
    }

    /// 한 장씩 디코드·렌더·인코드해 `dir` 에 쓴다. 메모리에는 한 번에 한 장만 올라간다.
    static func exportAll(_ jobs: [(PhotoSource, [RedactionItem])], to dir: URL) throws -> [URL] {
        try jobs.enumerated().map { i, job in
            try autoreleasepool {
                let (image, png) = try job.0.load()
                let data = try encode(render(image, items: job.1), png: png)
                let name = jobs.count == 1 ? "PrivacyCam_safe" : "PrivacyCam_safe_\(i + 1)"
                let url = dir.appendingPathComponent("\(name).\(png ? "png" : "jpg")")
                try data.write(to: url, options: [.atomic, .completeFileProtection])
                return url
            }
        }
    }

    static func thumbnail(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(src, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 1600,
        ] as CFDictionary)
    }

    /// 메타데이터 없이 다시 인코딩하고, 읽어 들여 제거됐는지 검증한다.
    static func encode(_ image: CGImage, png: Bool) throws -> Data {
        let data = NSMutableData()
        let type = (png ? UTType.png : UTType.jpeg).identifier as CFString
        guard let dest = CGImageDestinationCreateWithData(data, type, 1, nil) else { throw ImageError.renderFailed }
        CGImageDestinationAddImage(dest, image, png ? nil : [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ImageError.renderFailed }
        guard !hasIdentifyingMetadata(data as Data) else { throw ImageError.metadataNotRemoved }
        return data as Data
    }

    /// ImageIO 가 JPEG 에 자동으로 넣는 색공간·픽셀 크기 외의 EXIF/GPS/TIFF/IPTC 가 있으면 true.
    static func hasIdentifyingMetadata(_ data: Data) -> Bool {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return true }
        let harmlessExif: Set<CFString> = [kCGImagePropertyExifColorSpace, kCGImagePropertyExifPixelXDimension, kCGImagePropertyExifPixelYDimension]
        let exif = (props[kCGImagePropertyExifDictionary] as? [CFString: Any]) ?? [:]
        return !Set(exif.keys).isSubset(of: harmlessExif)
            || [kCGImagePropertyGPSDictionary, kCGImagePropertyTIFFDictionary, kCGImagePropertyIPTCDictionary,
                kCGImagePropertyMakerAppleDictionary].contains { props[$0] != nil }
    }
}
