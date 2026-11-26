import SwiftUI

// ponytail: SleepOffScreen `Components.swift` 에서 이 앱이 쓰는 것만 옮겼다. 필요해지면 원본에서 더 가져온다

extension View {
    /// 흰(다크는 남색) 카드. 라이트에서만 옅은 그림자를 준다
    func card(padding: CGFloat = 16) -> some View {
        modifier(Card(padding: padding))
    }

    /// 화면 아래에 떠 있는 확인 버튼 자리. iOS 26 부터 유리 버튼, 그 전은 검은 알약
    func bottomAction<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        safeAreaInset(edge: .bottom) {
            Group {
                if #available(iOS 26, *) {
                    content()
                        .font(.nunito(.body, .semibold))
                        .buttonStyle(.glassProminent)
                        .buttonSizing(.flexible)
                        .controlSize(.extraLarge)
                } else {
                    content().buttonStyle(.pill)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 8)
        }
    }
}

private struct Card: ViewModifier {
    let padding: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: shape)
            .overlay(shape.strokeBorder(Theme.stroke))
            .shadow(color: .black.opacity(scheme == .light ? 0.06 : 0), radius: 16, y: 6)
    }
}

/// 카드 화면 골격. 옅은 배경 위에 섹션을 28 간격으로 쌓는다
struct CardScroll<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 28) { content }
                .padding(16)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
    }
}

/// 제목 · 카드 · 설명 한 묶음. 카드 안의 행 사이에는 구분선을 넣는다
struct CardSection<Content: View>: View {
    let title: LocalizedStringKey?
    let footer: Text?
    let content: Content

    init(_ title: LocalizedStringKey? = nil, footer: Text? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 12) {
            if let title { SectionTitle(title) }
            VStack(alignment: .leading, spacing: 12) {
                Group(subviews: content) { rows in
                    ForEach(rows) { row in
                        if row.id != rows.first?.id { Divider() }
                        row
                    }
                }
            }
            .card()
            if let footer {
                footer
                    .font(.nunito(.footnote))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
        }
    }
}

/// 카드 묶음 위의 굵은 제목
struct SectionTitle: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.nunito(.title3, .bold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// List 의 시스템 배경을 걷어내고 테마 배경을 깐다. 행에는 `.listRowBackground(Theme.surface)`
    func themedList() -> some View {
        scrollContentBackground(.hidden).listSectionSpacing(.compact).background(Theme.background)
    }
}

/// 알약 버튼. 주 버튼은 검은 알약, 보조는 회색 알약
struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }

    var kind = Kind.primary
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .body) private var height = 52

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.nunito(.body, .semibold))
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

/// fill 원 안의 심볼 버튼. 누르는 동안 살짝 줄어든다 (Breathwrk·Opal 의 − / +)
struct RoundButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .title2) private var size = 56

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title2.weight(.semibold))
            .frame(width: size, height: size)
            .background(Theme.fill, in: .circle)
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == RoundButtonStyle {
    static var round: RoundButtonStyle { RoundButtonStyle() }
}

extension Font {
    /// 타이머·스테퍼 값처럼 largeTitle 보다 큰 숫자. Dynamic Type 에 맞춰 커진다
    static func display(_ size: CGFloat) -> Font {
        Font(Nunito.bold.uiFont(size: size, relativeTo: .largeTitle))
    }
}

/// 초를 "m:ss" 로. 예: 40 → "0:40"
func clock(_ seconds: Int) -> String {
    Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
}
