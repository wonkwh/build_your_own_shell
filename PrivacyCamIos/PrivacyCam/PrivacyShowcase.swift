import SwiftUI

private let forest = Color(red: 0x14 / 255, green: 0x6B / 255, blue: 0x55 / 255)
private let mint = Color(red: 0xE4 / 255, green: 0xF3 / 255, blue: 0xEC / 255)

/// 홈의 "보호 결과 보기" 카드. 에셋 `showcase_N_1`(원본)·`showcase_N_2`(보호본) 쌍을 비교한다.
struct PrivacyShowcase: View {
    static let pairCount = 4
    @State private var index = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(forest)
                    .frame(width: 38, height: 38)
                    .background(mint, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("보호 결과 보기").font(.headline.weight(.heavy))
                    Text("사진을 드래그해 비교하세요").font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Label("온디바이스", systemImage: "iphone")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(forest)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(mint.opacity(0.6), in: Capsule())
            }
            .padding(.horizontal, 5)

            BeforeAfterComparison(original: "showcase_\(index)_1", protected: "showcase_\(index)_2")
                .id(index)
                .transition(.opacity)

            HStack(spacing: 7) {
                Image(systemName: "hand.draw").foregroundStyle(forest)
                Text("핸들을 밀어 보세요. 사진은 기기 밖으로 나가지 않습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("이전 예시", systemImage: "chevron.left") { withAnimation { index -= 1 } }
                    .disabled(index == 1)
                Text("\(index)/\(Self.pairCount)").font(.caption.weight(.heavy)).monospacedDigit()
                Button("다음 예시", systemImage: "chevron.right") { withAnimation { index += 1 } }
                    .disabled(index == Self.pairCount)
            }
            .labelStyle(.iconOnly)
            .tint(forest)
            .padding(.horizontal, 5)
        }
        .padding(EdgeInsets(top: 14, leading: 12, bottom: 12, trailing: 12))
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Color(.separator).opacity(0.5)))
        .shadow(color: .black.opacity(0.07), radius: 12, y: 10)
    }
}

/// 보호본 위에 원본을 왼쪽부터 `reveal` 비율만큼 겹쳐 보여 주는 스와이프 비교.
struct BeforeAfterComparison: View {
    let original: String
    let protected: String
    @State private var reveal: CGFloat = 0.5

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                photo(protected, size)
                photo(original, size)
                    .mask(alignment: .leading) { Rectangle().frame(width: size.width * reveal) }
                HStack {
                    badge("원본", .black.opacity(0.68))
                    Spacer()
                    badge("보호됨", forest.opacity(0.92))
                }
                .padding(10)
                Rectangle().fill(.white.opacity(0.95))
                    .frame(width: 2, height: size.height)
                    .offset(x: size.width * reveal - 1)
                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(forest)
                    .frame(width: 40, height: 40)
                    .background(.white, in: Circle())
                    .overlay(Circle().strokeBorder(forest.opacity(0.28)))
                    .shadow(color: .black.opacity(0.2), radius: 5, y: 3)
                    .offset(x: size.width * reveal - 20, y: size.height / 2 - 20)
            }
            .contentShape(Rectangle())
            // 스크롤과 함께 받되, 가로로 움직일 때만 핸들을 옮긴다. 탭한 위치로도 이동.
            .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { v in
                guard abs(v.translation.width) >= abs(v.translation.height) else { return }
                reveal = clamp(v.location.x / size.width)
            })
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 19))
        .accessibilityElement()
        .accessibilityLabel("원본과 보호본 비교")
        .accessibilityValue("원본 \(Int(reveal * 100))퍼센트 보임")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: reveal = clamp(reveal + 0.1)
            case .decrement: reveal = clamp(reveal - 0.1)
            @unknown default: break
            }
        }
    }

    private func clamp(_ v: CGFloat) -> CGFloat { min(max(v, 0.04), 0.96) }

    private func photo(_ name: String, _ size: CGSize) -> some View {
        Image(name).resizable().scaledToFill().frame(width: size.width, height: size.height).clipped()
            .accessibilityHidden(true)
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(color, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.22)))
    }
}

/// 쇼케이스 원본(`showcase_N_1`)을 골라 바로 검사해 볼 수 있는 시트.
struct SamplePicker: View {
    let onPick: (String) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(1...PrivacyShowcase.pairCount, id: \.self) { n in
                        let name = "showcase_\(n)_1"
                        Button { onPick(name) } label: {
                            Color.clear
                                .aspectRatio(3 / 4, contentMode: .fit)
                                .overlay { Image(name).resizable().scaledToFill() }
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .accessibilityLabel("샘플 \(n)")
                    }
                }
                .padding()
            }
            .navigationTitle("샘플 사진")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    ScrollView { PrivacyShowcase().padding() }
}
