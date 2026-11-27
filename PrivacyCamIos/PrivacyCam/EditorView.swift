import Photos
import SwiftUI

struct EditorView: View {
    let batch: Batch
    @Environment(\.dismiss) private var dismiss
    @State private var current = 0
    @State private var image: CGImage?
    @State private var preview: CGImage?
    @State private var showPreview = false
    @State private var addingBox = false
    @State private var dragRect: CGRect?
    @State private var exported: Exported?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                canvas.frame(maxHeight: .infinity)
                categoryBar
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .task { for page in batch.pages where !Task.isCancelled { await page.scan() } }
            .task(id: current) { await loadImage() }
            .task(id: showPreview ? session.items : nil) { if showPreview { await renderPreview() } }
            .sheet(item: $exported) { ExportSheet(exported: $0) }
            .onDisappear { if let pdf = batch.pdf { try? FileManager.default.removeItem(at: pdf.url) } }
            .alert("오류", isPresented: .constant(error != nil)) {
                Button("확인") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private var session: EditSession { batch.pages[current] }

    private var title: String {
        let base = session.scanning ? "검사 중…" : "검토"
        return batch.pages.count > 1 ? "\(base) \(current + 1)/\(batch.pages.count)" : base
    }

    /// 보고 있는 사진만 디코드해 둔다. 페이지를 넘기면 이전 이미지는 버린다.
    private func loadImage() async {
        image = nil
        preview = nil
        showPreview = false
        addingBox = false
        let (page, source) = (session, session.source)
        do {
            let loaded = try await Task.detached(priority: .userInitiated) { try source.load().image }.value
            guard !Task.isCancelled else { return }
            image = loaded
        } catch {
            page.failed = true
        }
    }

    // MARK: 캔버스

    @ViewBuilder private var canvas: some View {
        if let image {
            canvas(image)
        } else {
            ZStack {
                Theme.background
                if session.failed {
                    Text("이 사진은 열 수 없어 내보내기에서 뺍니다.").foregroundStyle(Theme.caution)
                } else {
                    ProgressView()
                }
            }
        }
    }

    private func canvas(_ image: CGImage) -> some View {
        GeometryReader { geo in
            let imageSize = CGSize(width: image.width, height: image.height)
            let scale = min(geo.size.width / imageSize.width, geo.size.height / imageSize.height)
            let fitted = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
            ZStack(alignment: .topLeading) {
                Image(decorative: showPreview ? (preview ?? image) : image, scale: 1)
                    .resizable()
                    .frame(width: fitted.width, height: fitted.height)
                if !showPreview {
                    ForEach(Bindable(session).items) { $item in
                        let r = item.bounds.applying(.init(scaleX: scale, y: scale))
                        // 가릴 상자는 accent 실선, 끈 상자는 사진 위에서 보이도록 흰 점선
                        Rectangle()
                            .fill(item.selected ? Theme.accent.opacity(0.25) : .clear)
                            .strokeBorder(item.selected ? Theme.accent : .white.opacity(0.85),
                                          style: StrokeStyle(lineWidth: 2, dash: item.selected ? [] : [5]))
                            .frame(width: r.width, height: r.height)
                            .offset(x: r.minX, y: r.minY)
                            .onTapGesture { item.selected.toggle() }
                            .accessibilityLabel("\(item.category.label) \(item.selected ? "가림" : "가리지 않음")")
                            .accessibilityAddTraits(.isButton)
                    }
                }
                if let dragRect {
                    Rectangle().strokeBorder(Theme.accent, lineWidth: 2)
                        .frame(width: dragRect.width, height: dragRect.height)
                        .offset(x: dragRect.minX, y: dragRect.minY)
                }
            }
            .frame(width: fitted.width, height: fitted.height)
            .contentShape(Rectangle())
            .gesture(addBoxGesture(scale: scale, size: imageSize), isEnabled: addingBox)
            .overlay { if session.scanning { ProgressView().controlSize(.large) } }
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .background(Theme.background)
    }

    private func addBoxGesture(scale: CGFloat, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { v in
                dragRect = CGRect(x: min(v.startLocation.x, v.location.x), y: min(v.startLocation.y, v.location.y),
                                  width: abs(v.location.x - v.startLocation.x), height: abs(v.location.y - v.startLocation.y))
            }
            .onEnded { _ in
                defer { dragRect = nil }
                guard let r = dragRect, r.width > 8, r.height > 8 else { return }
                let bounds = CGRect(origin: .zero, size: size)
                session.items.append(RedactionItem(.manual, r.applying(.init(scaleX: 1 / scale, y: 1 / scale)).intersection(bounds)))
            }
    }

    // MARK: 카테고리 바

    private var categoryBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(presentCategories, id: \.self) { category in
                        categoryMenu(category)
                    }
                }
                .padding(.horizontal)
            }
            Text(session.scanning ? " " : session.items.isEmpty
                ? "찾은 항목이 없습니다. 필요한 곳은 직접 상자를 그려 가리세요."
                : "자동 검출은 완벽하지 않습니다. 저장 전에 직접 확인하세요. 상자를 탭하면 켜고 끕니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            if batch.skipped > 0 {
                Text("불러오지 못한 사진 \(batch.skipped)장은 빠졌습니다.")
                    .font(.footnote)
                    .foregroundStyle(Theme.caution)
                    .padding(.horizontal)
            }
        }
        .padding(.vertical, 12)
        .background(Theme.background)
        .overlay(alignment: .top) { Theme.stroke.frame(height: 1) }
    }

    private var presentCategories: [RedactionCategory] {
        RedactionCategory.allCases.filter { c in session.items.contains { $0.category == c } }
    }

    private func categoryMenu(_ category: RedactionCategory) -> some View {
        let indices = session.items.indices.filter { session.items[$0].category == category }
        let on = indices.filter { session.items[$0].selected }.count
        return Menu {
            Toggle("가리기", isOn: Binding(
                get: { on == indices.count },
                set: { v in indices.forEach { session.items[$0].selected = v } }))
            Picker("스타일", selection: Binding(
                get: { session.items[indices[0]].style },
                set: { s in indices.forEach { session.items[$0].style = s } })) {
                ForEach(RedactionStyle.allCases, id: \.self) { Text($0.label) }
            }
        } label: {
            Text("\(category.label) \(on)/\(indices.count)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(on > 0 ? Theme.accent : .secondary)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(on > 0 ? Theme.accent.opacity(0.12) : Theme.fill, in: Capsule())
        }
    }

    // MARK: 툴바

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("닫기") { dismiss() }
        }
        ToolbarItemGroup(placement: .bottomBar) {
            Toggle(isOn: $addingBox) { Label("상자 추가", systemImage: "plus.rectangle") }
                .disabled(showPreview || image == nil)
            Spacer()
            if batch.pages.count > 1 {
                Button("이전 사진", systemImage: "chevron.left") { current -= 1 }
                    .disabled(current == 0)
                Button("다음 사진", systemImage: "chevron.right") { current += 1 }
                    .disabled(current == batch.pages.count - 1)
                Spacer()
            }
            Toggle(isOn: $showPreview) { Label("미리보기", systemImage: "eye") }
                .disabled(image == nil)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("내보내기") { Task { await export() } }
                .disabled(batch.pages.contains(where: \.scanning) || batch.pages.allSatisfy(\.failed))
        }
    }

    // MARK: 렌더링

    private func renderPreview() async {
        guard let image else { return }
        let items = session.items
        preview = try? await Task.detached { try Renderer.render(image, items: items) }.value
    }

    /// 열지 못한 사진은 빼고 모두 내보낸다. PDF 는 쪽을 빼지 않고 한 파일로.
    private func export() async {
        let pdfName = batch.pdf?.name
        let jobs = batch.pages.filter { pdfName != nil || !$0.failed }.map { ($0.source, $0.items) }
        do {
            let (urls, thumb) = try await Task.detached {
                let dir = FileManager.default.temporaryDirectory
                if let pdfName {
                    let url = try PDFSupport.export(jobs, name: pdfName, to: dir)
                    return ([url], PDFSupport.thumbnail(url))
                }
                let urls = try Renderer.exportAll(jobs, to: dir)
                return (urls, urls.first.flatMap(Renderer.thumbnail))
            }.value
            exported = Exported(urls: urls, preview: thumb)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct Exported: Identifiable {
    let id = UUID()
    let urls: [URL]
    let preview: CGImage?
}

struct ExportSheet: View {
    let exported: Exported
    @State private var saved = false
    @State private var error: String?

    private var isPDF: Bool { exported.urls.first?.pathExtension == "pdf" }

    var body: some View {
        VStack(spacing: 16) {
            if let preview = exported.preview {
                Image(decorative: preview, scale: 1).resizable().scaledToFit()
                    .clipShape(.rect(cornerRadius: 14, style: .continuous))
            }
            if exported.urls.count > 1 {
                Text("첫 사진 미리보기 · 모두 \(exported.urls.count)장")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Label(isPDF ? "텍스트·메타데이터 없이 이미지로 다시 만들었습니다" : "위치·기기 정보 등 메타데이터를 제거했습니다",
                  systemImage: "checkmark.shield")
                .font(.footnote)
                .foregroundStyle(Theme.positive)
            if let error { Text(error).font(.footnote).foregroundStyle(Theme.caution) }
            if isPDF {
                // 파일 앱 저장은 공유 시트에 있다
                ShareLink(items: exported.urls) { Label("공유 또는 파일에 저장", systemImage: "square.and.arrow.up") }
                    .buttonStyle(.pill)
            } else {
                Button(saved ? "저장됨" : exported.urls.count > 1 ? "사진에 \(exported.urls.count)장 저장" : "사진에 저장", systemImage: saved ? "checkmark" : "square.and.arrow.down") {
                    Task { await save() }
                }
                .buttonStyle(.pill)
                .disabled(saved)
                ShareLink(items: exported.urls) { Label("공유", systemImage: "square.and.arrow.up") }
                    .buttonStyle(.pill(.secondary))
            }
        }
        .padding(16)
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.background)
        .onDisappear { exported.urls.forEach { try? FileManager.default.removeItem(at: $0) } }
    }

    private func save() async {
        guard await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized else {
            error = "설정에서 사진 추가 권한을 허용해 주세요."
            return
        }
        do {
            try await Self.addToPhotos(exported.urls)
            saved = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// 검증한 파일을 다시 인코딩하지 않고 그대로 추가한다.
    /// `performChanges` 블록은 백그라운드 큐에서 돌므로 MainActor 밖에서 만든다.
    nonisolated private static func addToPhotos(_ urls: [URL]) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            for url in urls {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: url, options: nil)
            }
        }
    }
}
