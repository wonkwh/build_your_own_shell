import AppKit
import SwiftUI

/// 앱 시작, 메뉴, 설정 창, 안내 문서.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settingsWindow: NSWindow?
    private var defaultsObserver: NSObjectProtocol?
    private var showsWelcome = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
        GlobalConfig.shared.ensureFiles()
        StyleSheets.ensureFolder()
        showsWelcome = !UserDefaults.standard.bool(forKey: "welcomeShown")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                for case let doc as OutlineDocument in NSDocumentController.shared.documents { doc.editor.restyleAll() }
            }
        }
        if showsWelcome {
            UserDefaults.standard.set(true, forKey: "welcomeShown")
            openWelcome(nil)
        }
    }

    /// 첫 실행에는 안내 문서만 연다.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { !showsWelcome }

    @objc func selectStyleSheet(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.title, forKey: "styleSheet")
    }

    @objc func openStyleSheetFolder(_ sender: Any?) {
        StyleSheets.ensureFolder()
        NSWorkspace.shared.open(StyleSheets.folder)
    }

    @objc func openUsersGuide(_ sender: Any?) {
        NSWorkspace.shared.open(URL(string: "https://www.taskpaper.com/guide/")!)
    }

    @objc func showPreferences(_ sender: Any?) {
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "설정"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            settingsWindow = w
        }
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// 안내 문서를 새 제목 없는 문서로 연다.
    @objc func openWelcome(_ sender: Any?) {
        guard let url = Bundle.main.url(forResource: "Welcome", withExtension: "taskpaper"),
              let text = try? String(contentsOf: url, encoding: .utf8),
              let doc = try? NSDocumentController.shared.makeUntitledDocument(ofType: "com.hogbaysoftware.taskpaper.document") as? OutlineDocument
        else { return }
        try? doc.read(from: Data(text.utf8), ofType: "com.hogbaysoftware.taskpaper.document")
        NSDocumentController.shared.addDocument(doc)
        doc.makeWindowControllers()
        doc.showWindows()
    }
}
