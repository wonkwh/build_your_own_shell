import AVFoundation
import CoreImage
import Foundation

enum VideoError: LocalizedError {
    case unreadable, tooLong, exportFailed

    var errorDescription: String? {
        switch self {
        case .unreadable: "동영상을 열 수 없습니다. 손상되었거나 지원하지 않는 형식입니다."
        case .tooLong: "동영상은 \(Int(VideoSupport.maxSeconds))초까지 처리할 수 있습니다."
        case .exportFailed: "가린 동영상을 만들지 못했습니다."
        }
    }
}

/// 트랙의 한 시점 위치. `rect` 는 화면 기준 0...1 좌표(좌상단 원점).
struct Keyframe: Sendable {
    var t: Double
    var rect: CGRect
}

/// 프레임 사이에 이어 붙인 한 대상. 검출한 시점 사이는 선형 보간한다.
struct VideoTrack: Identifiable, Sendable, Maskable {
    let id = UUID()
    let category: RedactionCategory
    var keyframes: [Keyframe]
    var selected: Bool
    var style: RedactionStyle

    init(_ category: RedactionCategory, first: Keyframe) {
        self.category = category
        keyframes = [first]
        selected = category.selectedByDefault
        style = category.defaultStyle
    }

    /// 처음 검출 전·마지막 검출 뒤로 더 가리는 시간. 텍스트는 검사 간격만큼.
    var hold: Double { VideoSupport.isText(category) ? VideoSupport.textInterval : VideoSupport.interval * 1.5 }

    /// `t` 초의 위치. 움직임에 대비해 사방 8% 넓힌다. 트랙 밖이면 nil.
    func rect(at t: Double) -> CGRect? {
        guard let first = keyframes.first, let last = keyframes.last,
              t >= first.t - hold, t <= last.t + hold else { return nil }
        let r: CGRect
        if t <= first.t { r = first.rect } else if t >= last.t { r = last.rect } else {
            let j = keyframes.firstIndex { $0.t >= t }!
            let (a, b) = (keyframes[j - 1], keyframes[j])
            let f = (t - a.t) / (b.t - a.t)
            func mix(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * f }
            r = CGRect(x: mix(a.rect.minX, b.rect.minX), y: mix(a.rect.minY, b.rect.minY),
                       width: mix(a.rect.width, b.rect.width), height: mix(a.rect.height, b.rect.height))
        }
        return r.insetBy(dx: -r.width * 0.08, dy: -r.height * 0.08).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }
}

/// 동영상을 일정 간격으로 검사해 트랙을 만들고, 모든 프레임에 같은 렌더러로 가려 MP4 로 내보낸다.
enum VideoSupport {
    static let freeSeconds = 15.0
    static let maxSeconds = 60.0
    static let interval = 0.3
    // ponytail: 텍스트 인식이 가장 무거워 3초마다. 화면에 잠깐 스치는 글자는 놓칠 수 있다.
    static let textInterval = 3.0

    static func isText(_ c: RedactionCategory) -> Bool {
        [.email, .phone, .address, .card, .cardSecurityCode, .url, .otherText].contains(c)
    }

    /// 길이(초)와 회전을 반영한 화면 크기.
    static func inspect(_ url: URL) async throws -> (duration: Double, size: CGSize) {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw VideoError.unreadable }
        let (natural, transform) = try await track.load(.naturalSize, .preferredTransform)
        let s = natural.applying(transform)
        return (try await asset.load(.duration).seconds, CGSize(width: abs(s.width), height: abs(s.height)))
    }

    struct Sample: Sendable {
        let t: Double
        let items: [(category: RedactionCategory, rect: CGRect)]
    }

    /// `interval` 마다 프레임을 꺼내 검출하고 트랙으로 묶는다. 취소하면 멈춘다.
    static func analyze(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> [VideoTrack] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1920, height: 1920)
        let tolerance = CMTime(value: 1, timescale: 30)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        let times = Array(stride(from: 0.0, to: max(duration, 0.01), by: interval))
        var samples: [Sample] = []
        var lastText = -Double.infinity
        for (i, t) in times.enumerated() {
            try Task.checkCancellation()
            let (image, actual) = try await generator.image(at: CMTime(seconds: t, preferredTimescale: 600))
            let withText = actual.seconds - lastText >= textInterval - 0.01
            if withText { lastText = actual.seconds }
            let w = CGFloat(image.width), h = CGFloat(image.height)
            let items = await Detector.detect(image, includeText: withText).map {
                ($0.category, CGRect(x: $0.bounds.minX / w, y: $0.bounds.minY / h, width: $0.bounds.width / w, height: $0.bounds.height / h))
            }
            samples.append(Sample(t: actual.seconds, items: items))
            progress(Double(i + 1) / Double(times.count))
        }
        return buildTracks(samples)
    }

    /// 같은 카테고리에서 가장 가까운 직전 위치에 잇는다. 너무 오래 끊기면 새 트랙.
    static func buildTracks(_ samples: [Sample]) -> [VideoTrack] {
        var tracks: [VideoTrack] = []
        for sample in samples {
            var claimed = Set<UUID>()
            for item in sample.items {
                let maxGap = (isText(item.category) ? textInterval : interval) * 2.5
                var best: (index: Int, score: CGFloat)?
                for (i, track) in tracks.enumerated() where track.category == item.category && !claimed.contains(track.id) {
                    let last = track.keyframes[track.keyframes.count - 1]
                    guard sample.t - last.t <= maxGap else { continue }
                    let distance = hypot(last.rect.midX - item.rect.midX, last.rect.midY - item.rect.midY)
                    let iou = last.rect.iou(item.rect)
                    guard iou >= 0.1 || distance <= max(last.rect.width, last.rect.height) * 0.75 else { continue }
                    let score = iou - distance
                    if best == nil || score > best!.score { best = (i, score) }
                }
                let keyframe = Keyframe(t: sample.t, rect: item.rect)
                if let best {
                    tracks[best.index].keyframes.append(keyframe)
                    claimed.insert(tracks[best.index].id)
                } else {
                    let track = VideoTrack(item.category, first: keyframe)
                    claimed.insert(track.id)
                    tracks.append(track)
                }
            }
        }
        return tracks
    }

    /// 켠 트랙을 모든 프레임에 굽고 메타데이터 없이 `MaskShare_video.mp4` 로 쓴다.
    static func export(_ url: URL, tracks: [VideoTrack], muteAudio: Bool, to dir: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard let video = try await asset.loadTracks(withMediaType: .video).first else { throw VideoError.unreadable }
        let range = CMTimeRange(start: .zero, duration: try await asset.load(.duration))
        // 원본 컨테이너의 위치·기기 정보는 새 컴포지션으로 옮겨지지 않는다
        let composition = AVMutableComposition()
        guard let v = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw VideoError.exportFailed }
        try v.insertTimeRange(range, of: video, at: .zero)
        v.preferredTransform = try await video.load(.preferredTransform)
        if !muteAudio, let audio = try await asset.loadTracks(withMediaType: .audio).first,
           let a = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try a.insertTimeRange(range, of: audio, at: .zero)
        }

        let selected = tracks.filter(\.selected)
        let videoComposition = try await AVVideoComposition.videoComposition(with: composition) { request in
            let source = request.sourceImage
            let size = source.extent.size
            let t = request.compositionTime.seconds
            let items = selected.compactMap { track -> RedactionItem? in
                guard let r = track.rect(at: t) else { return nil }
                var item = RedactionItem(track.category, CGRect(x: r.minX * size.width, y: r.minY * size.height,
                                                                width: r.width * size.width, height: r.height * size.height))
                item.selected = true
                item.style = track.style
                return item
            }
            request.finish(with: Renderer.apply(source, items: items), context: nil)
        }

        let out = dir.appendingPathComponent("MaskShare_video.mp4")
        try? FileManager.default.removeItem(at: out)
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
        else { throw VideoError.exportFailed }
        session.videoComposition = videoComposition
        session.metadata = []
        session.metadataItemFilter = .forSharing()
        do {
            if #available(iOS 18, *) {
                try await session.export(to: out, as: .mp4)
            } else {
                session.outputURL = out
                session.outputFileType = .mp4
                await session.export()
                if let error = session.error { throw error }
                guard session.status == .completed else { throw VideoError.exportFailed }
            }
            guard try await !hasIdentifyingMetadata(out) else { throw ImageError.metadataNotRemoved }
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: out.path)
            return out
        } catch {
            try? FileManager.default.removeItem(at: out)
            throw error
        }
    }

    /// 위치·기기 제조사·모델·소프트웨어 정보가 남아 있으면 true.
    static func hasIdentifyingMetadata(_ url: URL) async throws -> Bool {
        let risky: Set<AVMetadataIdentifier> = [
            .commonIdentifierLocation, .quickTimeMetadataLocationISO6709, .commonIdentifierMake, .commonIdentifierModel,
            .quickTimeMetadataMake, .quickTimeMetadataModel, .commonIdentifierSoftware, .quickTimeMetadataSoftware,
        ]
        let items = try await AVURLAsset(url: url).load(.metadata)
        return items.contains { $0.identifier.map(risky.contains) ?? false }
    }

    static func thumbnail(_ url: URL) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1600, height: 1600)
        return try? await generator.image(at: .zero).image
    }
}
