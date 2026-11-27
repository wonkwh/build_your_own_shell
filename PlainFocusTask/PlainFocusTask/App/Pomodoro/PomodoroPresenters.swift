import AppKit
import SwiftUI

/// 메뉴 막대·미니 창·전체 화면·통계 창을 띄우고 닫는다.
final class PomodoroPresenters: NSObject, NSWindowDelegate {
    private unowned let controller: PomodoroController
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var mini: NSPanel?
    private var fullScreen: NSWindow?
    private var stats: NSWindow?

    init(controller: PomodoroController) {
        self.controller = controller
        super.init()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PomodoroView())
    }

    func apply(_ s: PomodoroSettings) {
        if s.showMenuBar, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.target = self
            item.button?.action = #selector(statusClicked)
            item.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            statusItem = item
        } else if !s.showMenuBar, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        if s.showMiniWindow { showMini() } else { mini?.orderOut(nil) }
        refresh()
    }

    /// 1초마다: 메뉴 막대 제목을 남은 시간으로 바꾼다.
    func refresh() {
        guard let button = statusItem?.button else { return }
        let t = controller.timer
        button.title = t.started ? (t.phase.isBreak ? "☕️ " : "🍅 ") + controller.timeText : "🍅"
        button.toolTip = controller.task.map { "\(controller.phaseTitle) · \($0.title)" } ?? controller.phaseTitle
    }

    @objc private func statusClicked() {
        guard let button = statusItem?.button else { return }
        if popover.isShown { popover.performClose(nil) } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: 미니 창

    func showMini() {
        if mini == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 300),
                                styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .utilityWindow],
                                backing: .buffered, defer: false)
            panel.title = "뽀모도로"
            panel.titlebarAppearsTransparent = true
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isMovableByWindowBackground = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: PomodoroView(style: .compact))
            panel.delegate = self
            panel.setFrameAutosaveName("PomodoroMini")
            if panel.frame.origin == .zero { panel.center() }
            mini = panel
        }
        mini?.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSPanel === mini { controller.update { $0.showMiniWindow = false } }
        if notification.object as? NSWindow === fullScreen { fullScreen = nil }
    }

    // MARK: 전체 화면

    func toggleFullScreen() {
        if let w = fullScreen { w.close(); return }
        guard let screen = NSApp.mainWindow?.screen ?? NSScreen.main else { return }
        let w = EscapableWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.level = .statusBar
        w.backgroundColor = .windowBackgroundColor
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.contentView = NSHostingView(rootView: PomodoroView(style: .large).frame(maxWidth: .infinity, maxHeight: .infinity))
        w.setFrame(screen.frame, display: true)
        w.makeKeyAndOrderFront(nil)
        fullScreen = w
    }

    // MARK: 통계

    func showStats() {
        if stats == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: PomodoroStatsView()))
            w.title = "뽀모도로 통계"
            w.setContentSize(NSSize(width: 520, height: 600))
            w.isReleasedWhenClosed = false
            w.setFrameAutosaveName("PomodoroStats")
            stats = w
        }
        stats?.makeKeyAndOrderFront(nil)
    }
}

/// Esc로 닫히는 테두리 없는 창(전체 화면 타이머)
private final class EscapableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { close() }
}
