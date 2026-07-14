import AppKit
import Combine
import Foundation
@preconcurrency import UserNotifications

@MainActor
final class PomodoroTimer: ObservableObject {
    enum State: Equatable {
        case idle
        case running
        case paused
        case completed
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var remainingSeconds: Int
    private(set) var configuredSeconds: Int
    private let clock = ContinuousClock()
    private var timerTask: Task<Void, Never>?
    private var deadline: ContinuousClock.Instant?

    init(minutes: Int = 25) {
        configuredSeconds = max(1, minutes * 60)
        remainingSeconds = configuredSeconds
    }

    init(seconds: Int) {
        configuredSeconds = max(1, seconds)
        remainingSeconds = configuredSeconds
    }

    var formattedRemaining: String {
        String(format: "%02d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }

    var configuredMinutes: Int {
        max(1, Int(ceil(Double(configuredSeconds) / 60)))
    }

    var remainingProgress: Double {
        guard configuredSeconds > 0 else { return 0 }
        return min(1, max(0, Double(remainingSeconds) / Double(configuredSeconds)))
    }

    func configure(minutes: Int) {
        guard state == .idle || state == .completed else { return }
        deadline = nil
        configuredSeconds = max(1, minutes * 60)
        remainingSeconds = configuredSeconds
        state = .idle
    }

    func start() {
        if state == .completed {
            remainingSeconds = configuredSeconds
        }
        guard state != .running else { return }
        deadline = clock.now.advanced(by: .seconds(remainingSeconds))
        state = .running
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let self else { return }
                self.synchronizeToDeadline()
            }
        }
    }

    func pause() {
        guard state == .running else { return }
        synchronizeToDeadline()
        guard state == .running else { return }
        timerTask?.cancel()
        timerTask = nil
        deadline = nil
        state = .paused
    }

    func reset() {
        timerTask?.cancel()
        timerTask = nil
        deadline = nil
        remainingSeconds = configuredSeconds
        state = .idle
    }

    func tick(notifyOnCompletion: Bool = true) {
        guard state == .running else { return }
        remainingSeconds = max(0, remainingSeconds - 1)
        guard remainingSeconds == 0 else { return }
        complete(notifyOnCompletion: notifyOnCompletion)
    }

    private func synchronizeToDeadline(notifyOnCompletion: Bool = true) {
        guard state == .running, let deadline else { return }
        let duration = clock.now.duration(to: deadline).components
        let exactSeconds = Double(duration.seconds)
            + Double(duration.attoseconds) / 1_000_000_000_000_000_000
        remainingSeconds = max(
            0,
            Int(ceil(exactSeconds))
        )
        guard remainingSeconds == 0 else { return }
        complete(notifyOnCompletion: notifyOnCompletion)
    }

    private func complete(notifyOnCompletion: Bool) {
        timerTask?.cancel()
        timerTask = nil
        deadline = nil
        state = .completed
        NSSound(named: "Glass")?.play()
        if notifyOnCompletion {
            notifyCompletion()
        }
    }

    private func notifyCompletion() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Joi says: focus block complete!"
            content.body = "Lovely work. Stretch, hydrate, and choose your next step."
            content.sound = .default
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}
