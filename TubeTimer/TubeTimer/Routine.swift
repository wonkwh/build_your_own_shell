import Foundation
import SwiftData

/// 운동·할일 루틴. 할일은 세트 1, 휴식 0 인 루틴이다
@Model
final class Routine {
    var name: String
    var sets: Int
    var work: Int
    var rest: Int
    /// 붙여넣은 영상 링크 (YouTube · mp4). YouTube 시작 시각은 링크의 `t=` 로 둔다
    var videoURL: URL?
    var createdAt: Date

    init(name: String = "인터벌", sets: Int = 8, work: Int = 40, rest: Int = 20, videoURL: URL? = nil, createdAt: Date = .now) {
        self.name = name
        self.sets = sets
        self.work = work
        self.rest = rest
        self.videoURL = videoURL
        self.createdAt = createdAt
    }

    var plan: IntervalPlan { IntervalPlan(sets: sets, work: work, rest: rest) }

    var video: VideoSource? { videoURL.flatMap { VideoSource(url: $0) } }
}

extension Routine {
    /// 예전 버전이 `@AppStorage` 에 둔 설정 키
    static let legacyKeys = ["sets", "work", "rest"]

    /// 루틴이 하나도 없으면 첫 루틴을 만든다. 예전 설정이 있으면 그 값으로 만들고 키를 지운다
    static func seedIfNeeded(in context: ModelContext, defaults: UserDefaults = .standard) throws {
        guard try context.fetchCount(FetchDescriptor<Routine>()) == 0 else { return }
        let routine = Routine()
        routine.sets = defaults.object(forKey: "sets") as? Int ?? routine.sets
        routine.work = defaults.object(forKey: "work") as? Int ?? routine.work
        routine.rest = defaults.object(forKey: "rest") as? Int ?? routine.rest
        context.insert(routine)
        try context.save()
        legacyKeys.forEach(defaults.removeObject)
    }
}
