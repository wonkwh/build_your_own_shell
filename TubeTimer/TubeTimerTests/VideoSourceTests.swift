import Foundation
import SwiftData
import Testing
@testable import TubeTimer

struct VideoSourceTests {
    @Test(arguments: [
        ("https://www.youtube.com/watch?v=dQw4w9WgXcQ", 0),
        ("https://youtu.be/dQw4w9WgXcQ?si=abc", 0),
        ("youtu.be/dQw4w9WgXcQ", 0),
        ("  https://m.youtube.com/watch?v=dQw4w9WgXcQ&t=90\n", 90),
        ("https://youtube.com/shorts/dQw4w9WgXcQ", 0),
        ("https://www.youtube.com/live/dQw4w9WgXcQ?t=1m30s", 90),
        ("https://www.youtube.com/embed/dQw4w9WgXcQ?start=12", 12),
        ("https://music.youtube.com/watch?v=dQw4w9WgXcQ&t=1h2m3s", 3723),
    ])
    func parsesYouTube(link: String, start: Int) {
        #expect(VideoSource(string: link) == .youtube(YouTubeVideo(id: "dQw4w9WgXcQ", start: start)))
    }

    @Test(arguments: [
        "https://cdn.example.com/workout.mp4",
        "https://cdn.example.com/a/b/Clip.MOV?token=1",
        "cdn.example.com/live/index.m3u8",
    ])
    func parsesVideoFile(link: String) throws {
        let source = try #require(VideoSource(string: link))
        guard case .file(let url) = source else { Issue.record("파일로 읽지 않음: \(source)"); return }
        #expect(url.scheme == "https")
    }

    @Test(arguments: [
        "",
        "hello",
        "https://www.youtube.com/watch?v=short",
        "https://www.youtube.com/@channel",
        "https://vimeo.com/123456",
        "https://example.com/page.html",
        "http://cdn.example.com/workout.mp4",
    ])
    func rejects(link: String) {
        #expect(VideoSource(string: link) == nil)
    }

    @Test func badStartTimeKeepsVideo() {
        #expect(VideoSource(string: "https://youtu.be/dQw4w9WgXcQ?t=abc") == .youtube(YouTubeVideo(id: "dQw4w9WgXcQ")))
    }

    @Test func youTubeLinks() {
        let video = YouTubeVideo(id: "dQw4w9WgXcQ", start: 90)
        #expect(video.watchURL.absoluteString == "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=90s")
        #expect(video.thumbnailURL.absoluteString == "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg")
    }
}

@MainActor
struct RoutineSeedTests {
    let context = ModelContext(try! ModelContainer(for: Routine.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    let defaults = UserDefaults(suiteName: "RoutineSeedTests-\(UUID())")!

    @Test func movesLegacySettings() throws {
        defaults.set(5, forKey: "sets")
        defaults.set(30, forKey: "work")
        defaults.set(0, forKey: "rest")
        try Routine.seedIfNeeded(in: context, defaults: defaults)

        let routines = try context.fetch(FetchDescriptor<Routine>())
        #expect(routines.map(\.plan) == [IntervalPlan(sets: 5, work: 30, rest: 0)])
        #expect(Routine.legacyKeys.allSatisfy { defaults.object(forKey: $0) == nil })
    }

    @Test func seedsDefaultsOnce() throws {
        try Routine.seedIfNeeded(in: context, defaults: defaults)
        try Routine.seedIfNeeded(in: context, defaults: defaults)

        let routines = try context.fetch(FetchDescriptor<Routine>())
        #expect(routines.map(\.plan) == [IntervalPlan(sets: 8, work: 40, rest: 20)])
    }
}
