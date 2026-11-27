import AVKit
import Combine
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// 사진 앱에서 고른 동영상을 앱 임시 폴더로 복사해 받는다.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).appendingPathExtension(received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self(url: copy)
        }
    }
}

/// 동영상 한 개의 분석 상태와 트랙.
@MainActor @Observable
final class VideoSession: Identifiable {
    let url: URL
    let size: CGSize
    var tracks: [VideoTrack] = []
    var progress = 0.0
    var analyzing = true
    var failed: String?
    var muteAudio = false

    init(url: URL, size: CGSize) {
        self.url = url
        self.size = size
    }

    /// 화면이 닫혀 작업이 취소되면 분석도 멈춘다.
    func analyze() async {
        let url = url
        let task = Task.detached(priority: .userInitiated) {
            try await VideoSupport.analyze(url) { p in Task { @MainActor in self.progress = p } }
        }
        do {
            tracks = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        } catch is CancellationError {
            return
        } catch {
            failed = error.localizedDescription
        }
        analyzing = false
    }
}

struct VideoEditorView: View {
    let session: VideoSession
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer
    @State private var time = 0.0
    @State private var exporting = false
    @State private var exported: Exported?
    @State private var error: String?
    // ponytail: 재생 위치를 짧은 간격으로 읽는다. 상자가 끊겨 보이면 periodic time observer 로.
    private let tick = Timer.publish(every: 1.0 / 20, on: .main, in: .common).autoconnect()

    init(session: VideoSession) {
        self.session = session
        _player = State(initialValue: AVPlayer(url: session.url))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VideoPlayer(player: player)
                    .aspectRatio(session.size, contentMode: .fit)
                    .overlay { if !session.analyzing { GeometryReader { boxes(in: $0.size) } } }
                    .overlay { if session.analyzing { progressCard("분석 중 \(Int(session.progress * 100))%", value: session.progress) } }
                    .overlay { if exporting { progressCard("내보내는 중…", value: nil) } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
                categoryBar
            }
            .navigationTitle(session.analyzing ? "검사 중…" : "검토")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .task { await session.analyze() }
            .onReceive(tick) { _ in time = player.currentTime().seconds }
            .onDisappear {
                player.pause()
                try? FileManager.default.removeItem(at: session.url)
            }
            .sheet(item: $exported) { ExportSheet(exported: $0) }
            .alert("오류", isPresented: .constant(error != nil)) {
                Button("확인") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    /// 지금 재생 위치에 걸린 트랙만 그린다. 가릴 상자는 accent 실선, 끈 상자는 흰 점선.
    private func boxes(in size: CGSize) -> some View {
        ForEach(Bindable(session).tracks) { $track in
            if let r = track.rect(at: time) {
                Rectangle()
                    .fill(track.selected ? Theme.accent.opacity(0.25) : .clear)
                    .strokeBorder(track.selected ? Theme.accent : .white.opacity(0.85),
                                  style: StrokeStyle(lineWidth: 2, dash: track.selected ? [] : [5]))
                    .frame(width: r.width * size.width, height: r.height * size.height)
                    .position(x: r.midX * size.width, y: r.midY * size.height)
                    .onTapGesture { track.selected.toggle() }
                    .accessibilityLabel("\(track.category.label) \(track.selected ? "가림" : "가리지 않음")")
                    .accessibilityAddTraits(.isButton)
            }
        }
    }

    private func progressCard(_ title: String, value: Double?) -> some View {
        VStack(spacing: 10) {
            if let value { ProgressView(value: value) } else { ProgressView() }
            Text(title).font(.footnote.weight(.semibold))
        }
        .frame(width: 200)
        .padding(16)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
    }

    private var categoryBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(presentCategories, id: \.self) { category in
                        CategoryMenu(items: Bindable(session).tracks, category: category)
                    }
                }
                .padding(.horizontal)
            }
            Group {
                if let failed = session.failed {
                    Text(failed).foregroundStyle(Theme.caution)
                } else {
                    Text(session.analyzing ? "동영상을 훑어보며 가릴 곳을 찾고 있습니다."
                        : session.tracks.isEmpty ? "찾은 항목이 없습니다."
                        : "자동 검출은 완벽하지 않습니다. 재생하며 확인하세요. 상자를 탭하면 켜고 끕니다.")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.footnote)
            .padding(.horizontal)
        }
        .padding(.vertical, 12)
        .background(Theme.background)
        .overlay(alignment: .top) { Theme.stroke.frame(height: 1) }
    }

    private var presentCategories: [RedactionCategory] {
        RedactionCategory.allCases.filter { c in session.tracks.contains { $0.category == c } }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("닫기") { dismiss() }
        }
        ToolbarItem(placement: .bottomBar) {
            Toggle(isOn: Bindable(session).muteAudio) { Label("소리 끄기", systemImage: session.muteAudio ? "speaker.slash" : "speaker.wave.2") }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("내보내기") { Task { await export() } }
                .disabled(session.analyzing || exporting || session.failed != nil)
        }
    }

    private func export() async {
        player.pause()
        exporting = true
        defer { exporting = false }
        let (url, tracks, mute) = (session.url, session.tracks, session.muteAudio)
        do {
            let out = try await Task.detached(priority: .userInitiated) {
                try await VideoSupport.export(url, tracks: tracks, muteAudio: mute, to: FileManager.default.temporaryDirectory)
            }.value
            exported = Exported(urls: [out], preview: await VideoSupport.thumbnail(out))
        } catch {
            self.error = error.localizedDescription
        }
    }
}
