import Foundation

/// 루틴에 붙이는 영상. YouTube 링크 또는 mp4 같은 영상 파일 링크
nonisolated enum VideoSource: Equatable {
    case youtube(YouTubeVideo)
    /// AVPlayer 로 재생하는 영상 파일
    case file(URL)

    /// AVPlayer 가 재생하는 형식. http 는 ATS 가 막으므로 https 만 받는다
    private static let fileExtensions: Set = ["mp4", "m4v", "mov", "m3u8"]

    /// 붙여넣은 글자. 앞뒤 공백과 `https://` 가 없는 링크도 받는다
    init?(string: String) {
        let text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text.contains("://") ? text : "https://" + text) else { return nil }
        self.init(url: url)
    }

    init?(url: URL) {
        if let video = YouTubeVideo(url: url) {
            self = .youtube(video)
        } else if url.scheme?.lowercased() == "https", url.host != nil,
                  Self.fileExtensions.contains(url.pathExtension.lowercased()) {
            self = .file(url)
        } else {
            return nil
        }
    }

    /// 저장할 링크. YouTube 는 시작 시각을 담은 watch 링크로 맞춘다
    var url: URL {
        switch self {
        case .youtube(let video): video.watchURL
        case .file(let url): url
        }
    }

    /// 목록·미리보기에 보일 제목. YouTube 는 oEmbed(API 키 없음), 파일은 파일 이름
    func fetchTitle() async -> String? {
        switch self {
        case .youtube(let video):
            struct OEmbed: Decodable { let title: String }
            var components = URLComponents(string: "https://www.youtube.com/oembed")!
            components.queryItems = [URLQueryItem(name: "url", value: video.watchURL.absoluteString), URLQueryItem(name: "format", value: "json")]
            guard let (data, _) = try? await URLSession.shared.data(from: components.url!) else { return nil }
            return try? JSONDecoder().decode(OEmbed.self, from: data).title
        case .file(let url):
            return url.deletingPathExtension().lastPathComponent
        }
    }
}

/// YouTube 링크에서 꺼낸 영상 ID 와 시작 시각
nonisolated struct YouTubeVideo: Equatable {
    let id: String
    /// 시작 시각(초). 링크의 `t=` · `start=`
    var start = 0

    private static let hosts: Set = ["youtube.com", "m.youtube.com", "music.youtube.com", "youtube-nocookie.com", "youtu.be"]
    private static let idCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")

    init(id: String, start: Int = 0) {
        self.id = id
        self.start = start
    }

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              var host = components.host?.lowercased() else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        guard Self.hosts.contains(host) else { return nil }

        let path = components.path.split(separator: "/").map(String.init)
        let query = components.queryItems ?? []
        let id: String? = switch (host, path.first) {
        case ("youtu.be", _): path.first
        case (_, "watch"): query.first { $0.name == "v" }?.value
        case (_, "shorts"), (_, "live"), (_, "embed"), (_, "v"): path.dropFirst().first
        default: nil
        }
        guard let id, id.count == 11, id.unicodeScalars.allSatisfy(Self.idCharacters.contains) else { return nil }

        self.id = id
        let time = query.first { $0.name == "t" || $0.name == "start" }?.value
        start = time.flatMap(Self.seconds) ?? 0
    }

    /// YouTube 앱·사파리로 여는 링크
    var watchURL: URL {
        var components = URLComponents(string: "https://www.youtube.com/watch")!
        components.queryItems = [URLQueryItem(name: "v", value: id)] + (start > 0 ? [URLQueryItem(name: "t", value: "\(start)s")] : [])
        return components.url!
    }

    var thumbnailURL: URL {
        URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg")!
    }

    /// "90", "90s", "1m30s", "1h2m3s" → 초
    private static func seconds(_ text: String) -> Int? {
        if let plain = Int(text) { return plain }
        var total = 0, number = 0, sawUnit = false
        for character in text {
            if let digit = character.wholeNumberValue {
                number = number * 10 + digit
                continue
            }
            switch character {
            case "h": total += number * 3600
            case "m": total += number * 60
            case "s": total += number
            default: return nil
            }
            number = 0
            sawUnit = true
        }
        return sawUnit && number == 0 ? total : nil
    }
}
