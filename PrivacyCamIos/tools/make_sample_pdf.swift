import AppKit
import CoreImage
// 샘플 PDF 생성: swift tools/make_sample_pdf.swift MaskShare/Samples/MaskShare_Sample.pdf <showcase_4_1 에서 세 사람만 잘라낸 jpg>
let a = CommandLine.arguments
var media = CGRect(x: 0, y: 0, width: 595, height: 842)
let ctx = CGContext(URL(fileURLWithPath: a[1]) as CFURL, mediaBox: &media, [kCGPDFContextCreator: "MaskShare"] as CFDictionary)!
let accent = NSColor(red: 0x5B/255, green: 0x67/255, blue: 0xD8/255, alpha: 1)
let ink = NSColor(white: 0.1, alpha: 1), gray = NSColor(white: 0.45, alpha: 1), line = NSColor(white: 0.85, alpha: 1)

func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ color: NSColor = ink, bold: Bool = false) {
    (s as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size), .foregroundColor: color])
}
func rule(_ y: CGFloat) { line.setFill(); NSRect(x: 48, y: y, width: 499, height: 0.75).fill() }
func header(_ title: String, _ page: Int) {
    accent.setFill(); NSRect(x: 0, y: 782, width: 595, height: 60).fill()
    text(title, 48, 800, 22, .white, bold: true)
    text("Page \(page) of 2", 480, 806, 11, .white)
    text("SAMPLE DOCUMENT · All names, numbers and addresses are fictional.", 48, 758, 9, gray)
}
func field(_ label: String, _ value: String, _ y: CGFloat) {
    text(label.uppercased(), 48, y + 18, 8.5, gray, bold: true)
    text(value, 48, y, 15)
    rule(y - 10)
}
func begin() { ctx.beginPDFPage(nil); NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false) }

// 1쪽: 신청서
begin()
header("Rental Application", 1)
text("Applicant", 48, 712, 13, accent, bold: true)
field("Full name", "Alex Morgan", 672)
field("Email", "alex.morgan@example.com", 626)
field("Mobile", "+1 415 555 0134", 580)
text("CURRENT ADDRESS", 48, 552, 8.5, gray, bold: true)
text("1200 Harbor View Road, Apt 4B", 48, 534, 15)
text("San Francisco, CA 94107", 48, 514, 15); rule(504)
text("Payment", 48, 462, 13, accent, bold: true)
field("Card number", "4242 4242 4242 4242", 422)
field("Expiry / CVV", "VALID THRU 08/29   CVV 123", 376)
field("Monthly rent", "2,450.00 USD", 330)
text("I confirm the information above is accurate.", 48, 250, 11, gray)
text("Signed: Alex Morgan        Date: 2026-11-27", 48, 226, 11, ink)
ctx.endPDFPage()

// 2쪽: 동거인 사진과 QR
begin()
header("Photo & Verification", 2)
text("Co-applicants", 48, 712, 13, accent, bold: true)
let photo = NSImage(contentsOfFile: a[2])!
let photoH = 499 * photo.size.height / photo.size.width
photo.draw(in: NSRect(x: 48, y: 736 - photoH, width: 499, height: photoH))
text("Photo submitted with the application", 48, 718 - photoH, 10, gray)
let vy = 672 - photoH
text("Verification", 48, vy, 13, accent, bold: true)
let qr = CIFilter(name: "CIQRCodeGenerator", parameters: ["inputMessage": "https://example.com/applications/2026-114".data(using: .utf8)!, "inputCorrectionLevel": "M"])!.outputImage!
let big = qr.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
let cg = CIContext().createCGImage(big, from: big.extent)!
ctx.interpolationQuality = .none
ctx.draw(cg, in: CGRect(x: 48, y: vy - 176, width: 150, height: 150))
text("Scan to open application #2026-114", 220, vy - 66, 12, ink)
text("Reference: 2026-114", 220, vy - 90, 12, ink)
text("Contact: leasing@example.com", 220, vy - 114, 12, ink)
ctx.endPDFPage()
ctx.closePDF()
