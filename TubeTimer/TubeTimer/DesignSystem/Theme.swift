import SwiftUI
import UIKit

/// SleepOffScreen Night Card 토큰. 쓰임은 `../SleepOffScreen/DESIGN.md`
enum Theme {
    static let background = Color(light: 0xF2F2F6, dark: 0x141A2E)
    /// 카드·패널. 다크는 반투명이라 밤 배경이 비친다
    static let surface = Color(light: 0xFFFFFF, dark: 0xA9B6FF, darkOpacity: 0.08)
    static let fill = Color(light: 0xECECF1, dark: 0x2A3252)
    /// 카드·패널·차트의 1px 테두리
    static let stroke = Color(light: 0x000000, dark: 0xFFFFFF, lightOpacity: 0.05, darkOpacity: 0.08)
    static let accent = Color(light: 0x5B67D8, dark: 0x8F9BFF)
    static let positive = Color(light: 0x2E9E5E, dark: 0x4CC983)
    static let ink = Color(light: 0x1C1C1E, dark: 0xECEEFA)
    static let onInk = Color(light: 0xFFFFFF, dark: 0x141A2E)

    static let cardRadius: CGFloat = 22
}

private extension Color {
    /// 시스템 모드에 따라 라이트·다크 hex 중 하나로 그려지는 색
    init(light: UInt32, dark: UInt32, lightOpacity: CGFloat = 1, darkOpacity: CGFloat = 1) {
        self.init(uiColor: .dynamic(light: light, dark: dark, lightOpacity: lightOpacity, darkOpacity: darkOpacity))
    }
}

private extension UIColor {
    /// SwiftUI 가 렌더 스레드에서 부를 수 있으므로 main actor 에 묶지 않는다
    nonisolated static func dynamic(light: UInt32, dark: UInt32, lightOpacity: CGFloat, darkOpacity: CGFloat) -> UIColor {
        UIColor {
            $0.userInterfaceStyle == .dark ? UIColor(hex: dark, alpha: darkOpacity) : UIColor(hex: light, alpha: lightOpacity)
        }
    }

    nonisolated convenience init(hex: UInt32, alpha: CGFloat) {
        self.init(
            red: CGFloat(hex >> 16 & 0xFF) / 255,
            green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
