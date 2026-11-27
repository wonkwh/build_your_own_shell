import CoreGraphics
import Foundation
import ImageIO
import PDFKit

enum PDFError: LocalizedError {
    case unreadable, locked, tooManyPages, flattenFailed

    var errorDescription: String? {
        switch self {
        case .unreadable: "PDF 를 열 수 없습니다. 손상되었거나 지원하지 않는 형식입니다."
        case .locked: "암호가 걸린 PDF 는 아직 지원하지 않습니다."
        case .tooManyPages: "PDF 는 \(PDFSupport.maxPages)쪽까지 처리할 수 있습니다."
        case .flattenFailed: "텍스트가 남지 않았는지 확인하지 못해 내보내기를 중단했습니다."
        }
    }
}

/// PDF 를 페이지 이미지로 검사하고, 가린 이미지만으로 새 PDF 를 만든다. 원본의 텍스트·링크·메타데이터는 옮기지 않는다.
enum PDFSupport {
    static let freePageLimit = 2
    // ponytail: 페이지마다 다시 렌더하므로 상한은 처리 시간 기준. 더 필요하면 렌더 캐시를 둔다.
    static let maxPages = 50

    /// 고른 파일을 앱 임시 폴더로 복사하고 쪽수를 돌려준다.
    /// - Throws: 열 수 없거나 암호가 걸린 문서면 `PDFError`. 이때 복사본은 지운다.
    static func importFile(_ picked: URL) throws -> (url: URL, pageCount: Int) {
        let scoped = picked.startAccessingSecurityScopedResource()
        defer { if scoped { picked.stopAccessingSecurityScopedResource() } }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
        try FileManager.default.copyItem(at: picked, to: url)
        do {
            guard let doc = CGPDFDocument(url as CFURL) else { throw PDFError.unreadable }
            guard doc.isUnlocked else { throw PDFError.locked }
            guard doc.numberOfPages > 0 else { throw PDFError.unreadable }
            return (url, doc.numberOfPages)
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    /// `index` 쪽(0부터)을 긴 변 2400px 안팎의 이미지로 그린다.
    static func render(_ url: URL, page index: Int) throws -> CGImage {
        guard let page = CGPDFDocument(url as CFURL)?.page(at: index + 1) else { throw PDFError.unreadable }
        return try render(page)
    }

    static func render(_ page: CGPDFPage) throws -> CGImage {
        let size = pointSize(page)
        let scale = min(3, 2400 / max(size.width, size.height))
        let w = max(1, Int((size.width * scale).rounded())), h = max(1, Int((size.height * scale).rounded()))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw PDFError.unreadable }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: CGFloat(w) / size.width, y: CGFloat(h) / size.height)
        // 페이지 회전까지 반영한 변환
        ctx.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: size), rotate: 0, preserveAspectRatio: true))
        ctx.drawPDFPage(page)
        guard let image = ctx.makeImage() else { throw PDFError.unreadable }
        return image
    }

    /// 회전을 반영한 화면상 쪽 크기(포인트).
    static func pointSize(_ page: CGPDFPage) -> CGSize {
        let box = page.getBoxRect(.cropBox)
        return page.rotationAngle % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width)
    }

    /// 쪽마다 가린 이미지를 JPEG 로 넣어 `<name>_safe.pdf` 를 만들고, 텍스트 층이 없는지 검증한다.
    static func export(_ jobs: [(PhotoSource, [RedactionItem])], name: String, to dir: URL) throws -> URL {
        let out = dir.appendingPathComponent("\(name)_safe.pdf")
        try? FileManager.default.removeItem(at: out)
        guard let ctx = CGContext(out as CFURL, mediaBox: nil, [kCGPDFContextCreator: "PrivacyCam"] as CFDictionary)
        else { throw ImageError.renderFailed }
        do {
            for (source, items) in jobs {
                guard case .pdfPage(let url, let index) = source,
                      let page = CGPDFDocument(url as CFURL)?.page(at: index + 1) else { throw PDFError.unreadable }
                try autoreleasepool {
                    let jpeg = try Renderer.encode(Renderer.render(render(page), items: items), png: false)
                    // JPEG 에서 만든 CGImage 는 PDF 에 JPEG 그대로 들어가 용량이 작다
                    guard let src = CGImageSourceCreateWithData(jpeg as CFData, nil),
                          let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { throw ImageError.renderFailed }
                    var box = CGRect(origin: .zero, size: pointSize(page))
                    ctx.beginPage(mediaBox: &box)
                    ctx.draw(image, in: box)
                    ctx.endPage()
                }
            }
            ctx.closePDF()
            try verify(out, pages: jobs.count)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: out.path)
            return out
        } catch {
            try? FileManager.default.removeItem(at: out)
            throw error
        }
    }

    /// 쪽수가 맞고, 암호·선택 가능한 텍스트가 없어야 통과.
    static func verify(_ url: URL, pages: Int) throws {
        guard let doc = PDFDocument(url: url), !doc.isEncrypted, doc.pageCount == pages,
              (doc.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw PDFError.flattenFailed }
    }

    static func thumbnail(_ url: URL) -> CGImage? {
        guard let page = CGPDFDocument(url as CFURL)?.page(at: 1) else { return nil }
        return try? render(page)
    }
}
