import PhotosUI
import SwiftUI

@main
struct PrivacyCamApp: App {
    @State private var store = Store()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .tint(Theme.accent)
                .environment(store)
                .task { await store.observe() }
        }
    }
}

/// 사진 한 장의 검출 결과. 이미지는 들고 있지 않고 필요할 때 `source` 에서 디코드한다.
@MainActor @Observable
final class EditSession {
    let source: PhotoSource
    var items: [RedactionItem] = []
    var scanning = true
    var failed = false

    init(_ source: PhotoSource) { self.source = source }

    func scan() async {
        let source = source
        do {
            items = try await Task.detached(priority: .userInitiated) { await Detector.detect(try source.load().image) }.value
        } catch {
            failed = true
        }
        scanning = false
    }
}

struct Batch: Identifiable {
    let id = UUID()
    let pages: [EditSession]
    var skipped = 0

    @MainActor init(_ sources: [PhotoSource], skipped: Int = 0) {
        pages = sources.map { EditSession($0) }
        self.skipped = skipped
    }
}

struct HomeView: View {
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var captured: Data?
    @State private var showSamples = false
    @State private var sample: String?
    @State private var batch: Batch?
    @State private var error: String?
    @State private var showPaywall = false
    @Environment(\.colorScheme) private var scheme
    @Environment(Store.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image("Logo").resizable().frame(width: 26, height: 26).clipShape(.rect(cornerRadius: 7))
                    Text("PrivacyCam").font(.callout.weight(.bold))
                }
                .accessibilityElement(children: .combine)
                Text("공유하기 전에,\n기기 안에서 가립니다")
                    .font(.title.weight(.heavy))
                    .padding(.top, 18)
                Text("사진을 고르면 가릴 곳을 알아서 찾아 둡니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                PrivacyShowcase()
                    .padding(.top, 18)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background {
            ZStack(alignment: .top) {
                Theme.background
                if scheme == .dark {
                    LinearGradient(colors: [Theme.accent.opacity(0.3), Theme.accent.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 380)
                }
            }
            .ignoresSafeArea()
        }
        .safeAreaInset(edge: .bottom) { actions }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            pickerItems = []
            Task {
                var sources: [PhotoSource] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) { sources.append(.data(data)) }
                }
                if sources.isEmpty {
                    error = ImageError.unsupported.localizedDescription
                } else {
                    batch = Batch(sources, skipped: items.count - sources.count)
                }
            }
        }
        // 카메라가 완전히 닫힌 뒤 편집기를 띄워야 표시가 겹치지 않는다.
        .fullScreenCover(isPresented: $showCamera, onDismiss: {
            if let data = captured { captured = nil; batch = Batch([.data(data)]) }
        }) {
            CameraPicker { captured = $0 }.ignoresSafeArea()
        }
        .sheet(isPresented: $showSamples, onDismiss: {
            if let name = sample, let image = UIImage(named: name)?.cgImage {
                batch = Batch([.image(image)])
            }
            sample = nil
        }) {
            SamplePicker { sample = $0; showSamples = false }
        }
        .fullScreenCover(item: $batch) { EditorView(batch: $0) }
        .sheet(isPresented: $showPaywall) { ProPaywall() }
        .alert("열 수 없음", isPresented: .constant(error != nil)) {
            Button("확인") { error = nil }
        } message: { Text(error ?? "") }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            // ponytail: 원본 Data 를 메모리에 다 들고 있으므로 10장 상한. 더 필요하면 파일 URL 로 받는다.
            // 무료는 한 장씩, Pro 는 여러 장
            PhotosPicker(selection: $pickerItems, maxSelectionCount: store.isPro ? 10 : 1, selectionBehavior: .ordered, matching: .images) {
                HStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle")
                    Text("사진 선택")
                    if store.isPro { Text("최대 10장").font(.subheadline).opacity(0.6) }
                }
            }
            .buttonStyle(.pill)
            HStack(spacing: 10) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("촬영", systemImage: "camera") { showCamera = true }
                }
                Button("샘플로 해보기") { showSamples = true }
            }
            .buttonStyle(.pill(.secondary))
            if !store.isPro {
                Button("여러 장을 한 번에 처리하려면 Pro") { showPaywall = true }
                    .font(.footnote.weight(.semibold))
            }
            Label("사진은 기기 밖으로 나가지 않습니다", systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.background)
    }
}

/// ponytail: 시스템 카메라 UI. 커스텀 카메라 화면은 필요해지면 AVCaptureSession 으로.
struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let data = (info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 1) { parent.onCapture(data) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
