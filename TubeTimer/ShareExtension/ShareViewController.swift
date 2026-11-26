import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 공유 시트로 받은 YouTube·영상 링크로 새 루틴을 만든다. 저장소는 App Group 으로 앱과 같이 쓴다
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        let host = UIHostingController(rootView: ShareView(providers: items.flatMap { $0.attachments ?? [] }) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}

private struct ShareView: View {
    let providers: [NSItemProvider]
    let done: () -> Void
    @State private var status = Status.saving

    enum Status { case saving, saved(String), invalid, failed }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                switch status {
                case .saving:
                    ProgressView()
                case .saved(let name):
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(Theme.positive)
                    Text("루틴을 추가했어요").font(.headline)
                    Text(name).foregroundStyle(.secondary).multilineTextAlignment(.center)
                case .invalid:
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 48)).foregroundStyle(Theme.caution)
                    Text("YouTube 링크나 https 로 시작하는 mp4 링크만 추가할 수 있어요").multilineTextAlignment(.center)
                case .failed:
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 48)).foregroundStyle(Theme.caution)
                    Text("루틴을 저장하지 못했어요")
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("TubeTimer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("완료", action: done) }
            }
        }
        .tint(Theme.accent)
        .task { status = await save() }
    }

    /// 링크를 읽어 제목을 받고 기본 타이머로 루틴을 저장한다
    private func save() async -> Status {
        guard let source = await loadSource() else { return .invalid }
        let title = await source.fetchTitle()
        let routine = Routine(name: title ?? Routine.newName, videoURL: source.url)
        routine.videoTitle = title
        do {
            let context = ModelContext(try ModelContainer(for: Routine.self))
            context.insert(routine)
            try context.save()
            return .saved(routine.name)
        } catch {
            return .failed
        }
    }

    /// 첨부 중 처음으로 읽히는 영상 링크. URL 로 오거나(사파리, YouTube 앱) 글로 온다
    private func loadSource() async -> VideoSource? {
        for provider in providers {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL,
               let source = VideoSource(url: url) { return source }
            if let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String,
               let source = VideoSource(string: text) { return source }
        }
        return nil
    }
}
