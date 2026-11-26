import AudioToolbox
import UserNotifications

/// 실행 중 신호. 앞에 있을 때는 소리, 백그라운드에서는 구간마다 알림
enum Cues {
    // ponytail: iOS 기본 카메라 타이머 소리를 빌려 쓴다. 경로가 바뀌면 소리만 안 나므로 그때 번들에 소리 파일을 넣는다
    private static let tick = sound("camera_timer_countdown")
    private static let change = sound("camera_timer_final_second")
    private static let finish = sound("jbl_confirm")

    /// 구간 끝 3·2·1 초 소리
    static func countdown() { AudioServicesPlaySystemSound(tick) }

    /// 구간이 바뀌었을 때 소리. 루틴을 마쳤으면 다른 소리
    static func changed(done: Bool) { AudioServicesPlaySystemSound(done ? finish : change) }

    private static func sound(_ name: String) -> SystemSoundID {
        var id: SystemSoundID = 0
        AudioServicesCreateSystemSoundID(URL(filePath: "/System/Library/Audio/UISounds/\(name).caf") as CFURL, &id)
        return id
    }

    private static var center: UNUserNotificationCenter { .current() }

    /// 알림 권한을 묻는다. 이미 답했으면 창 없이 끝난다
    static func requestNotifications() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    /// 앱이 백그라운드로 갈 때 남은 구간 전환마다 알림을 예약한다
    /// - Parameter run: 진행 중인 실행. 멈춰 있으면 예약하지 않는다
    static func scheduleChanges(of run: IntervalRun) {
        // ponytail: 앱 하나에 예약 알림은 64개까지라 앞에서부터 자른다
        for (index, change) in run.upcomingChanges().prefix(64).enumerated() {
            let content = UNMutableNotificationContent()
            switch change.phase {
            case .work: content.title = String(localized: "운동 · 세트 \(change.set)/\(run.plan.sets)")
            case .rest: content.title = String(localized: "휴식")
            case .done: content.title = String(localized: "수고했어요! 루틴을 마쳤어요")
            }
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, change.date.timeIntervalSinceNow), repeats: false)
            center.add(UNNotificationRequest(identifier: "change-\(index)", content: content, trigger: trigger))
        }
    }

    /// 앞으로 돌아오거나 실행을 끝내면 예약한 알림을 지운다
    static func cancelChanges() {
        center.removeAllPendingNotificationRequests()
    }
}
