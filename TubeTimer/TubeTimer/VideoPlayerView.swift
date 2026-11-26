import AVKit
import SwiftUI
import WebKit

/// 실행 화면의 16:9 영상 플레이어. 재생할 수 없으면 썸네일 위에 바깥에서 여는 버튼을 띄운다
struct VideoPlayerView: View {
    let source: VideoSource
    @State private var isFailed = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        Color.black
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                if isFailed {
                    fallback
                } else {
                    switch source {
                    case .youtube(let video): YouTubePlayer(video: video) { isFailed = true }
                    case .file(let url): FilePlayer(url: url) { isFailed = true }
                    }
                }
            }
            .clipShape(.rect(cornerRadius: Theme.innerRadius, style: .continuous))
    }

    private var fallback: some View {
        VideoThumbnail(source: source)
            .overlay {
                ZStack {
                    Color.black.opacity(0.55)
                    VStack(spacing: 12) {
                        Text("여기서 재생할 수 없는 영상이에요")
                            .font(.nunito(.subheadline, .medium))
                            .foregroundStyle(.white)
                        Button(openTitle) { openURL(source.url) }
                            .buttonStyle(.pill)
                            .fixedSize()
                    }
                    .padding()
                }
            }
    }

    private var openTitle: LocalizedStringKey {
        switch source {
        case .youtube: "YouTube에서 열기"
        case .file: "Safari에서 열기"
        }
    }
}

/// 영상 파일 재생. 열 수 없으면(오프라인, 접근 막힘) `onFail`
private struct FilePlayer: View {
    let url: URL
    let onFail: () -> Void
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .task(id: url) {
                let asset = AVURLAsset(url: url)
                guard (try? await asset.load(.isPlayable)) == true else { return onFail() }
                player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            }
    }
}

/// YouTube IFrame Player API 를 띄운 웹뷰. 퍼가기 막힘(101·150)·오프라인 같은 오류면 `onFail`
private struct YouTubePlayer: UIViewRepresentable {
    let video: YouTubeVideo
    let onFail: () -> Void

    // IFrame API 가 origin 을 확인하므로 앱 번들 ID 로 만든 https 주소를 페이지 주소로 쓴다
    private static let origin = URL(string: "https://\(Bundle.main.bundleIdentifier ?? "tubetimer").app")!

    func makeCoordinator() -> Coordinator { Coordinator(onFail: onFail) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.userContentController.add(context.coordinator, name: "player")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.loadHTMLString(html, baseURL: Self.origin)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    // 영상 ID 는 파서가 [A-Za-z0-9_-] 11자로 확인했으므로 그대로 넣는다
    private var html: String {
        """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
        <style>html,body,#player{margin:0;width:100%;height:100%;background:#000;overflow:hidden}</style>
        </head><body><div id="player"></div>
        <script>
        function report(e) { webkit.messageHandlers.player.postMessage(String(e)) }
        function onYouTubeIframeAPIReady() {
          new YT.Player('player', {
            host: 'https://www.youtube-nocookie.com',
            videoId: '\(video.id)',
            playerVars: { playsinline: 1, rel: 0, start: \(video.start), origin: '\(Self.origin.absoluteString)' },
            events: { onError: function (e) { report(e.data) } }
          })
        }
        </script>
        <script src="https://www.youtube.com/iframe_api" onerror="report('offline')"></script>
        </body></html>
        """
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        let onFail: () -> Void

        init(onFail: @escaping () -> Void) { self.onFail = onFail }

        // ponytail: 오류만 받는다. 타이머와 재생을 묶을 때 상태 이벤트를 더한다
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            onFail()
        }

        /// 플레이어 안의 링크(YouTube 로고, 다른 영상)는 웹뷰를 벗어나지 않게 바깥 앱으로 연다
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard action.targetFrame?.isMainFrame == true, action.navigationType == .linkActivated,
                  let url = action.request.url else { return .allow }
            await UIApplication.shared.open(url)
            return .cancel
        }

        /// 새 창으로 여는 링크도 바깥 앱으로 연다
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url { UIApplication.shared.open(url) }
            return nil
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            onFail()
        }
    }
}

#Preview {
    VideoPlayerView(source: .youtube(YouTubeVideo(id: "dQw4w9WgXcQ")))
        .padding()
}
