import CoreGraphics
import Foundation

enum RedactionCategory: String, CaseIterable, Sendable {
    case face, person, email, phone, address, card, cardSecurityCode, url, qrCode, barcode, numberPlate, otherText, manual

    var label: String {
        switch self {
        case .face: "얼굴"
        case .person: "사람"
        case .email: "이메일"
        case .phone: "전화번호"
        case .address: "주소"
        case .card: "카드 번호"
        case .cardSecurityCode: "카드 보안코드"
        case .url: "URL"
        case .qrCode: "QR 코드"
        case .barcode: "바코드"
        case .numberPlate: "번호판"
        case .otherText: "기타 텍스트"
        case .manual: "수동"
        }
    }

    var selectedByDefault: Bool { ![.manual, .person, .otherText].contains(self) }

    var defaultStyle: RedactionStyle {
        switch self {
        case .face: .blur
        case .qrCode, .numberPlate: .pixelate
        default: .blackout
        }
    }
}

enum RedactionStyle: String, CaseIterable, Sendable {
    case blur, pixelate, blackout

    var label: String {
        switch self {
        case .blur: "흐림"
        case .pixelate: "모자이크"
        case .blackout: "검정 박스"
        }
    }
}

/// `bounds` 는 이미지 픽셀 좌표(좌상단 원점).
struct RedactionItem: Identifiable, Equatable, Sendable {
    let id = UUID()
    let category: RedactionCategory
    var bounds: CGRect
    var selected: Bool
    var style: RedactionStyle
    var confidence: Float?
    var label: String?

    init(_ category: RedactionCategory, _ bounds: CGRect, confidence: Float? = nil, label: String? = nil) {
        self.category = category
        self.bounds = bounds
        self.selected = category == .manual || category.selectedByDefault
        self.style = category.defaultStyle
        self.confidence = confidence
        self.label = label
    }
}

extension CGRect {
    func iou(_ other: CGRect) -> CGFloat {
        let i = intersection(other)
        guard !i.isNull, i.width > 0, i.height > 0 else { return 0 }
        let inter = i.width * i.height
        let union = width * height + other.width * other.height - inter
        return union <= 0 ? 0 : inter / union
    }

    /// 상하좌우 여백을 비율로 더한 뒤 `limit` 안으로 자른다.
    func padded(left: CGFloat, top: CGFloat, right: CGFloat, bottom: CGFloat, in limit: CGRect) -> CGRect {
        CGRect(x: minX - width * left, y: minY - height * top,
               width: width * (1 + left + right), height: height * (1 + top + bottom))
            .intersection(limit)
    }
}
