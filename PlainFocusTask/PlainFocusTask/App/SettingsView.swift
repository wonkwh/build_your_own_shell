import SwiftUI

/// 설정 창. 값은 `UserDefaults`에 저장되고 열린 문서에 바로 반영된다.
struct SettingsView: View {
    @AppStorage("fontFamily") private var fontFamily = ""
    @AppStorage("fontSize") private var fontSize = 14.0
    @AppStorage("lineHeight") private var lineHeight = 1.25
    @AppStorage("includeDateWhenDone") private var includeDateWhenDone = true
    @AppStorage("archiveAddsProject") private var archiveAddsProject = true
    @AppStorage("archiveRemovesTags") private var archiveRemovesTags = false

    var body: some View {
        Form {
            Section("글꼴") {
                Picker("글꼴", selection: $fontFamily) {
                    Text("시스템").tag("")
                    Text("세리프").tag("serif")
                    Text("고정폭").tag("mono")
                }
                Stepper("크기 \(Int(fontSize))pt", value: $fontSize, in: 9...36)
                Slider(value: $lineHeight, in: 1.0...2.0, step: 0.05) { Text("줄 간격 \(lineHeight, specifier: "%.2f")") }
            }
            Section("태그") {
                Toggle("@done에 날짜 넣기", isOn: $includeDateWhenDone)
                Toggle("보관할 때 @project 태그 붙이기", isOn: $archiveAddsProject)
                Toggle("보관할 때 @done 말고 다른 태그 지우기", isOn: $archiveRemovesTags)
            }
            Section("모든 문서에 쓰는 설정") {
                Button("사이드바 검색 편집…") { open(GlobalConfig.shared.searchesURL) }
                Button("사이드바 태그 목록 편집…") { open(GlobalConfig.shared.tagsURL) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
    }

    private func open(_ url: URL) {
        GlobalConfig.shared.ensureFiles()
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }
}
