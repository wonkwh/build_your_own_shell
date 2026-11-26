import CoreText
import SwiftUI
import UIKit

/// 앱 번들 `Fonts/` 의 Nunito 정적 굵기. 한글은 같은 굵기대의 나눔스퀘어라운드로 이어 그린다
enum Nunito: String, CaseIterable {
    case regular = "Regular", medium = "Medium", semibold = "SemiBold", bold = "Bold"

    var fontName: String { "Nunito-\(rawValue)" }
    /// Nunito 에 없는 한글 글리프를 맡는 글꼴. 나눔스퀘어라운드는 R·B 만 번들한다
    var hangulName: String { self == .semibold || self == .bold ? "NanumSquareRoundB" : "NanumSquareRoundR" }

    init(_ weight: Font.Weight) {
        self = switch weight {
        case .bold, .heavy, .black: .bold
        case .semibold: .semibold
        case .medium: .medium
        default: .regular
        }
    }

    /// 한글 대체 글꼴을 붙이고 `style` 의 Dynamic Type 크기로 키운 UIFont
    func uiFont(size: CGFloat, relativeTo style: UIFont.TextStyle) -> UIFont {
        let hangul = UIFontDescriptor(name: hangulName, size: size)
        let descriptor = UIFontDescriptor(name: fontName, size: size).addingAttributes([.cascadeList: [hangul]])
        return UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont(descriptor: descriptor, size: size))
    }
}

extension Font {
    /// Nunito(한글은 나눔스퀘어라운드)를 글자 스타일 크기로 쓴다.
    /// 굵기를 주지 않으면 스타일 기본 굵기다 (headline 만 semibold).
    /// ponytail: 그리는 시점의 글자 크기로 고정된다. 설정에서 크기를 바꾸면 화면을 다시 그릴 때 반영된다
    static func nunito(_ style: TextStyle, _ weight: Weight? = nil) -> Font {
        let file = Nunito(weight ?? (style == .headline ? .semibold : .regular))
        return Font(file.uiFont(size: style.baseSize, relativeTo: style.uiKit))
    }
}

extension Font.TextStyle {
    /// 기본 글자 크기(Large)에서의 pt. iOS 시스템 글자 스타일과 같다
    var baseSize: CGFloat {
        switch self {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        default: 17
        }
    }

    var uiKit: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .callout: .callout
        case .subheadline: .subheadline
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
}

enum Typography {
    /// 폰트를 등록하고 UIKit 이 그리는 내비 제목·세그먼트·탭 글자도 같은 글꼴로 맞춘다. 앱 시작 때 한 번
    static func setUp() {
        let names = Nunito.allCases.map(\.fontName) + ["NanumSquareRoundR", "NanumSquareRoundB"]
        let urls = names.compactMap { Bundle.main.url(forResource: $0, withExtension: "ttf") }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
        UINavigationBar.appearance().titleTextAttributes = [.font: Nunito.semibold.uiFont(size: 17, relativeTo: .headline)]
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: Nunito.bold.uiFont(size: 34, relativeTo: .largeTitle)]
        UISegmentedControl.appearance().setTitleTextAttributes([.font: Nunito.medium.uiFont(size: 13, relativeTo: .footnote)], for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: Nunito.semibold.uiFont(size: 13, relativeTo: .footnote)], for: .selected)
        UITabBarItem.appearance().setTitleTextAttributes([.font: Nunito.medium.uiFont(size: 10, relativeTo: .caption2)], for: .normal)
    }
}
