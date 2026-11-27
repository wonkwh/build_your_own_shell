import SwiftUI
import UIKit

/// SleepOffScreen 과 같은 색 토큰. 라이트는 옅은 회색 위 흰 카드, 다크는 밤 남색.
enum Theme {
    static let background = Color(light: 0xF2F2F6, dark: 0x141A2E)
    static let fill = Color(light: 0xECECF1, dark: 0x2A3252)
    /// 1px 구분선·테두리
    static let stroke = Color(light: 0x000000, dark: 0xFFFFFF, lightOpacity: 0.05, darkOpacity: 0.08)
    static let accent = Color(light: 0x5B67D8, dark: 0x8F9BFF)
    static let positive = Color(light: 0x2E9E5E, dark: 0x4CC983)
    static let caution = Color(light: 0xE26A2C, dark: 0xFF9F5A)
    /// 주 알약 버튼 바탕과 글자
    static let ink = Color(light: 0x1C1C1E, dark: 0xECEEFA)
    static let onInk = Color(light: 0xFFFFFF, dark: 0x141A2E)

    static let cardRadius: CGFloat = 22
}

/// 알약 버튼. 주 버튼은 ink 알약(한 화면에 하나), 보조는 fill 알약.
struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }

    var kind = Kind.primary
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .body) private var height = 52

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(kind == .primary ? Theme.onInk : Color.primary)
            .frame(maxWidth: .infinity, minHeight: height)
            .padding(.horizontal, 20)
            .background(kind == .primary ? Theme.ink : Theme.fill, in: .capsule)
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
    static func pill(_ kind: PillButtonStyle.Kind) -> PillButtonStyle { PillButtonStyle(kind: kind) }
}

private extension Color {
    init(light: UInt32, dark: UInt32, lightOpacity: CGFloat = 1, darkOpacity: CGFloat = 1) {
        self.init(uiColor: UIColor {
            $0.userInterfaceStyle == .dark ? UIColor(hex: dark, alpha: darkOpacity) : UIColor(hex: light, alpha: lightOpacity)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat) {
        self.init(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}
