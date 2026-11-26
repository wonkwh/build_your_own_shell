import AVFoundation
import SwiftUI

/// 16:9 영상 썸네일. YouTube 는 썸네일 이미지, 영상 파일은 첫 프레임, 영상이 없으면 타이머 심볼
struct VideoThumbnail: View {
    let source: VideoSource?
    var radius = Theme.innerRadius
    @State private var frame: UIImage?

    var body: some View {
        Theme.fill
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                switch source {
                case .youtube(let video):
                    AsyncImage(url: video.thumbnailURL) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                case .file:
                    if let frame {
                        Image(uiImage: frame).resizable().scaledToFill()
                    } else {
                        // 로딩 중이거나 첫 프레임을 뽑지 못한 파일(HLS, 접근 막힘)
                        Image(systemName: "film").font(.title3).foregroundStyle(.secondary)
                    }
                case nil:
                    Image(systemName: "timer").font(.title3).foregroundStyle(.secondary)
                }
            }
            .clipShape(.rect(cornerRadius: radius, style: .continuous))
            .task(id: source) {
                guard case .file(let url) = source else { return }
                frame = await Self.firstFrame(of: url)
            }
            .accessibilityHidden(true)
    }

    /// 영상 파일의 첫 프레임. HLS(m3u8) 처럼 뽑을 수 없으면 nil
    private static func firstFrame(of url: URL) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 360)
        guard let (image, _) = try? await generator.image(at: .zero) else { return nil }
        return UIImage(cgImage: image)
    }
}
