import PhotosUI
import SwiftUI

@main
struct PrivacyCamApp: App {
    var body: some Scene {
        WindowGroup { HomeView() }
    }
}

@MainActor @Observable
final class EditSession: Identifiable {
    let image: CGImage
    let isPNG: Bool
    var items: [RedactionItem] = []
    var scanning = true

    init(image: CGImage, isPNG: Bool) {
        self.image = image
        self.isPNG = isPNG
    }

    func scan() async {
        let image = image
        items = await Task.detached(priority: .userInitiated) { await Detector.detect(image) }.value
        scanning = false
    }
}

struct HomeView: View {
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var captured: Data?
    @State private var showSamples = false
    @State private var sample: String?
    @State private var session: EditSession?
    @State private var error: String?

    var body: some View {
        ScrollView {
        VStack(spacing: 20) {
            Image(systemName: "eye.slash.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
                .padding(.top, 24)
            Text("PrivacyCam").font(.largeTitle.bold())
            Text("공유하기 전에 얼굴, 번호판, 개인정보 텍스트, QR 코드를 기기 안에서 찾아 가립니다.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button { showSamples = true } label: {
                Label("샘플 사진", systemImage: "photo.stack")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("사진 선택", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { showCamera = true } label: {
                    Label("사진 촬영", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            PrivacyShowcase()
                .padding(.top, 8)
        }
        .padding(24)
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            pickerItem = nil
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { throw ImageError.unsupported }
                    open(data)
                } catch {
                    self.error = error.localizedDescription
                }
            }
        }
        // 카메라가 완전히 닫힌 뒤 편집기를 띄워야 표시가 겹치지 않는다.
        .fullScreenCover(isPresented: $showCamera, onDismiss: {
            if let data = captured { captured = nil; open(data) }
        }) {
            CameraPicker { captured = $0 }.ignoresSafeArea()
        }
        .sheet(isPresented: $showSamples, onDismiss: {
            if let name = sample, let image = UIImage(named: name)?.cgImage {
                session = EditSession(image: image, isPNG: false)
            }
            sample = nil
        }) {
            SamplePicker { sample = $0; showSamples = false }
        }
        .fullScreenCover(item: $session) { EditorView(session: $0) }
        .alert("열 수 없음", isPresented: .constant(error != nil)) {
            Button("확인") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func open(_ data: Data) {
        do {
            let loaded = try Renderer.load(data)
            session = EditSession(image: loaded.image, isPNG: loaded.isPNG)
        } catch {
            self.error = error.localizedDescription
        }
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
