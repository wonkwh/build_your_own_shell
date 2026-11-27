import PDFKit
import SwiftUI

/// 홈의 전후 비교. 원본에 대해 앱의 검출기를 실제로 돌려 찾은 영역을 상자로 보여 준다.
struct PrivacyShowcase: View {
    static let pairCount = 4
    @State private var index = 1
    @State private var detections: [Int: ShowcaseDetection] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BeforeAfterComparison(original: "showcase_\(index)_1", protected: "showcase_\(index)_2", detection: detections[index])
                .id(index)
                .transition(.opacity)
            HStack(spacing: 0) {
                ForEach(1...Self.pairCount, id: \.self) { n in
                    Button { withAnimation { index = n } } label: {
                        Capsule()
                            .fill(n == index ? Theme.accent : Theme.fill)
                            .frame(width: n == index ? 18 : 6, height: 6)
                            // 점은 작아도 누르는 영역은 넓게
                            .frame(minWidth: 28, minHeight: 32)
                            .contentShape(.rect)
                    }
                    .accessibilityLabel("예시 \(n)")
                    .accessibilityAddTraits(n == index ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                ForEach(["얼굴", "번호판", "개인정보 텍스트", "QR"], id: \.self) { label in
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Theme.accent.opacity(0.12), in: Capsule())
                }
            }
            .accessibilityElement(children: .combine)
        }
        .task(id: index) { await detect(index) }
    }

    private func detect(_ n: Int) async {
        guard detections[n] == nil, let image = UIImage(named: "showcase_\(n)_1")?.cgImage else { return }
        let items = await Task.detached(priority: .utility) { await Detector.detect(image) }.value
        withAnimation { detections[n] = ShowcaseDetection(size: CGSize(width: image.width, height: image.height), items: items.filter(\.selected)) }
    }
}

struct ShowcaseDetection {
    let size: CGSize
    let items: [RedactionItem]
}

/// 보호본 위에 원본을 왼쪽부터 `reveal` 비율만큼 겹쳐 보여 주는 스와이프 비교.
struct BeforeAfterComparison: View {
    let original: String
    let protected: String
    var detection: ShowcaseDetection?
    @State private var reveal: CGFloat = 0.42

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                photo(protected, size)
                photo(original, size)
                    .mask(alignment: .leading) { Rectangle().frame(width: size.width * reveal) }
                if let detection { boxes(detection, in: size) }
                HStack {
                    badge(Text("원본"), .white)
                    Spacer()
                    badge(Text("\(Image(systemName: "checkmark")) 보호됨"), Theme.positive)
                }
                .padding(10)
                Rectangle().fill(.white.opacity(0.95))
                    .frame(width: 2, height: size.height)
                    .offset(x: size.width * reveal - 1)
                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.onInk)
                    .frame(width: 40, height: 40)
                    .background(Theme.ink, in: Circle())
                    .shadow(color: .black.opacity(0.3), radius: 5, y: 3)
                    .offset(x: size.width * reveal - 20, y: size.height / 2 - 20)
            }
            .contentShape(Rectangle())
            // 스크롤과 함께 받되, 가로로 움직일 때만 핸들을 옮긴다. 탭한 위치로도 이동.
            .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { v in
                guard abs(v.translation.width) >= abs(v.translation.height) else { return }
                reveal = clamp(v.location.x / size.width)
            })
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel("원본과 보호본 비교")
        .accessibilityValue("원본 \(Int(reveal * 100))퍼센트 보임, 가릴 곳 \(detection?.items.count ?? 0)개")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: reveal = clamp(reveal + 0.1)
            case .decrement: reveal = clamp(reveal - 0.1)
            @unknown default: break
            }
        }
    }

    /// 이미지 픽셀 좌표를 `scaledToFill` 로 잘린 화면 좌표로 옮겨 상자를 그린다. 라벨은 3개 이하일 때만.
    private func boxes(_ d: ShowcaseDetection, in size: CGSize) -> some View {
        let s = max(size.width / d.size.width, size.height / d.size.height)
        let ox = (size.width - d.size.width * s) / 2, oy = (size.height - d.size.height * s) / 2
        return ForEach(d.items) { item in
            let r = CGRect(x: item.bounds.minX * s + ox, y: item.bounds.minY * s + oy,
                           width: item.bounds.width * s, height: item.bounds.height * s)
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Theme.accent, lineWidth: 2)
                .frame(width: r.width, height: r.height)
                // 위쪽 배지와 겹치지 않게, 위에 붙은 상자는 라벨을 아래에 단다
                .overlay(alignment: r.minY < 64 ? .bottomLeading : .topLeading) {
                    if d.items.count <= 3 {
                        Text("\(item.category.label) · \(item.style.label)")
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(Theme.onInk)
                            .fixedSize()
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Theme.accent, in: .rect(cornerRadius: 5))
                            .offset(y: r.minY < 64 ? 22 : -22)
                    }
                }
                .offset(x: r.minX, y: r.minY)
        }
        .accessibilityHidden(true)
    }

    private func clamp(_ v: CGFloat) -> CGFloat { min(max(v, 0.04), 0.96) }

    private func photo(_ name: String, _ size: CGSize) -> some View {
        Image(name).resizable().scaledToFill().frame(width: size.width, height: size.height).clipped()
            .accessibilityHidden(true)
    }

    private func badge(_ text: Text, _ color: Color) -> some View {
        text
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(.black.opacity(0.55), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
    }
}

/// 쇼케이스 원본(`showcase_N_1`)이나 샘플 PDF 를 골라 바로 검사해 볼 수 있는 시트.
struct SamplePicker: View {
    static let pdfName = "MaskShare_Sample.pdf"
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
                    Button { onPick(Self.pdfName) } label: {
                        Color.white
                            .aspectRatio(3 / 4, contentMode: .fit)
                            .overlay(alignment: .top) { pdfThumbnail?.resizable().scaledToFit() }
                            .overlay(alignment: .bottomLeading) {
                                Label("PDF 2쪽", systemImage: "doc.text")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8).padding(.vertical, 5)
                                    .background(Theme.accent, in: Capsule())
                                    .padding(8)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .accessibilityLabel("샘플 PDF")
                }
                .padding()
            }
            .navigationTitle("샘플")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.background)
    }

    private var pdfThumbnail: Image? {
        guard let url = Bundle.main.url(forResource: Self.pdfName, withExtension: nil),
              let page = PDFDocument(url: url)?.page(at: 0) else { return nil }
        return Image(uiImage: page.thumbnail(of: CGSize(width: 300, height: 424), for: .cropBox))
    }
}

#Preview {
    ScrollView { PrivacyShowcase().padding() }
}
