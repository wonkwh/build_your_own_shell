import HealthKit

/// 건강 앱에 남길 운동 종류. 루틴에 고르면 끝까지 마쳤을 때 운동 기록을 저장한다
nonisolated enum Workout: String, Codable, CaseIterable {
    case hiit, strength, yoga, pilates, stretching, dance

    var activityType: HKWorkoutActivityType {
        switch self {
        case .hiit: .highIntensityIntervalTraining
        case .strength: .traditionalStrengthTraining
        case .yoga: .yoga
        case .pilates: .pilates
        case .stretching: .flexibility
        case .dance: .cardioDance
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .hiit: "고강도 인터벌"
        case .strength: "근력 운동"
        case .yoga: "요가"
        case .pilates: "필라테스"
        case .stretching: "스트레칭"
        case .dance: "댄스"
        }
    }
}

/// 건강 앱 운동 기록 쓰기
enum Health {
    private static let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// 운동 기록 쓰기 권한을 묻는다. 이미 답했으면 창 없이 바로 끝난다
    static func requestAccess() async throws {
        try await store.requestAuthorization(toShare: [.workoutType()], read: [])
    }

    /// 마친 운동을 건강 앱에 저장한다
    /// - Parameters:
    ///   - workout: 운동 종류
    ///   - start: 시작 시각
    ///   - end: 끝난 시각
    static func save(_ workout: Workout, from start: Date, to end: Date) async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = workout.activityType
        configuration.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        try await builder.beginCollection(at: start)
        try await builder.endCollection(at: end)
        try await builder.finishWorkout()
    }
}
