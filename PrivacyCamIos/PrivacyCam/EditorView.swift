import Photos
import SwiftUI

struct EditorView: View {
    @Bindable var session: EditSession
    @Environment(\.dismiss) private var dismiss
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
            .navigationTitle(session.scanning ? "검사 중…" : "검토")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .task { await session.scan() }
            .task(id: showPreview ? session.items : nil) { if showPreview { await renderPreview() } }
            .sheet(item: $exported) { ExportSheet(exported: $0) }
            .alert("오류", isPresented: .constant(error != nil)) {
                Button("확인") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    // MARK: 캔버스

    private var canvas: some View {
        GeometryReader { geo in
            let imageSize = CGSize(width: session.image.width, height: session.image.height)
            let scale = min(geo.size.width / imageSize.width, geo.size.height / imageSize.height)
            let fitted = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
            ZStack(alignment: .topLeading) {
                Image(decorative: showPreview ? (preview ?? session.image) : session.image, scale: 1)
                    .resizable()
                    .frame(width: fitted.width, height: fitted.height)
                if !showPreview {
                    ForEach($session.items) { $item in
                        let r = item.bounds.applying(.init(scaleX: scale, y: scale))
                        Rectangle()
                            .fill(item.selected ? color(item.category).opacity(0.25) : .clear)
                            .strokeBorder(color(item.category), style: StrokeStyle(lineWidth: 2, dash: item.selected ? [] : [5]))
                            .frame(width: r.width, height: r.height)
                            .offset(x: r.minX, y: r.minY)
                            .onTapGesture { item.selected.toggle() }
                            .accessibilityLabel("\(item.category.label) \(item.selected ? "가림" : "가리지 않음")")
                            .accessibilityAddTraits(.isButton)
                    }
                }
                if let dragRect {
                    Rectangle().strokeBorder(.yellow, lineWidth: 2)
                        .frame(width: dragRect.width, height: dragRect.height)
                        .offset(x: dragRect.minX, y: dragRect.minY)
                }
            }
            .frame(width: fitted.width, height: fitted.height)
            .contentShape(Rectangle())
            .gesture(addBoxGesture(scale: scale), isEnabled: addingBox)
            .overlay { if session.scanning { ProgressView().controlSize(.large) } }
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .background(Color.black)
    }

    private func addBoxGesture(scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { v in
                dragRect = CGRect(x: min(v.startLocation.x, v.location.x), y: min(v.startLocation.y, v.location.y),
                                  width: abs(v.location.x - v.startLocation.x), height: abs(v.location.y - v.startLocation.y))
            }
            .onEnded { _ in
                defer { dragRect = nil }
                guard let r = dragRect, r.width > 8, r.height > 8 else { return }
                let bounds = CGRect(x: 0, y: 0, width: session.image.width, height: session.image.height)
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
        }
        .padding(.vertical, 12)
        .background(.bar)
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
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(color(category).opacity(on > 0 ? 0.25 : 0.08), in: Capsule())
                .overlay(Capsule().strokeBorder(color(category)))
        }
        .tint(.primary)
    }

    // MARK: 툴바

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("닫기") { dismiss() }
        }
        ToolbarItemGroup(placement: .bottomBar) {
            Toggle(isOn: $addingBox) { Label("상자 추가", systemImage: "plus.rectangle") }
                .disabled(showPreview)
            Spacer()
            Toggle(isOn: $showPreview) { Label("미리보기", systemImage: "eye") }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("내보내기") { Task { await export() } }
                .disabled(session.scanning)
        }
    }

    // MARK: 렌더링

    private func renderPreview() async {
        let (image, items) = (session.image, session.items)
        preview = try? await Task.detached { try Renderer.render(image, items: items) }.value
    }

    private func export() async {
        let (image, items, png) = (session.image, session.items, session.isPNG)
        do {
            let (rendered, data) = try await Task.detached {
                let r = try Renderer.render(image, items: items)
                return (r, try Renderer.encode(r, png: png))
            }.value
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("PrivacyCam_safe.\(png ? "png" : "jpg")")
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            exported = Exported(url: url, image: rendered)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func color(_ c: RedactionCategory) -> Color {
        switch c {
        case .face, .person: .pink
        case .numberPlate: .orange
        case .qrCode, .barcode: .purple
        case .manual: .yellow
        case .otherText: .gray
        default: .red
        }
    }
}

struct Exported: Identifiable {
    let id = UUID()
    let url: URL
    let image: CGImage
}

struct ExportSheet: View {
    let exported: Exported
    @State private var saved = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 16) {
            Image(decorative: exported.image, scale: 1).resizable().scaledToFit()
            Label("위치·기기 정보 등 메타데이터를 제거했습니다", systemImage: "checkmark.shield")
                .font(.footnote)
                .foregroundStyle(.green)
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            HStack {
                Button(saved ? "저장됨" : "사진에 저장", systemImage: saved ? "checkmark" : "square.and.arrow.down") {
                    Task { await save() }
                }
                .disabled(saved)
                ShareLink(item: exported.url)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .presentationDetents([.medium, .large])
        .onDisappear { try? FileManager.default.removeItem(at: exported.url) }
    }

    private func save() async {
        guard await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized else {
            error = "설정에서 사진 추가 권한을 허용해 주세요."
            return
        }
        do {
            try await Self.addToPhotos(exported.url)
            saved = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// 검증한 파일을 다시 인코딩하지 않고 그대로 추가한다.
    /// `performChanges` 블록은 백그라운드 큐에서 돌므로 MainActor 밖에서 만든다.
    nonisolated private static func addToPhotos(_ url: URL) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: url, options: nil)
        }
    }
}
